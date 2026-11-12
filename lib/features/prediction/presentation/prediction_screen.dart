import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/bakery_widgets.dart';
import '../../profile/domain/user_profile.dart';
import '../data/prediction_service.dart';
import '../domain/daily_prediction.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({required this.role, this.gateway, super.key});

  final UserRole role;
  final PredictionGateway? gateway;

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  late final PredictionGateway _gateway;
  String? _tomorrowDate;
  String? _selectedDate;
  List<DailyPrediction> _predictions = const [];
  String? _error;
  bool _loading = true;
  bool _generating = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? PredictionService();
    _load();
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as PredictionService).close();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await _gateway.getNextDayState();
      final date = _selectedDate ?? next.targetDate;
      final predictions = date == next.targetDate
          ? next.predictions
          : await _gateway.getByDate(date);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _tomorrowDate = next.targetDate;
        _selectedDate = date;
        _predictions = predictions;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _chooseDate() async {
    final tomorrow = DateTime.tryParse(_tomorrowDate ?? '');
    final selected = DateTime.tryParse(_selectedDate ?? '');
    if (tomorrow == null || selected == null || _generating) return;
    final date = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2000),
      lastDate: tomorrow,
      helpText: 'View saved predictions',
    );
    if (date == null || !mounted) return;
    final formatted =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    if (formatted == _selectedDate) return;
    setState(() {
      _selectedDate = formatted;
      _predictions = const [];
    });
    await _load();
  }

  Future<void> _generate() async {
    if (_generating ||
        _loading ||
        widget.role != UserRole.bakeryManager ||
        _selectedDate == null ||
        _selectedDate != _tomorrowDate ||
        _predictions.isNotEmpty) {
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      await _gateway.generateNextDay();
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.code == 'PREDICTION_ALREADY_EXISTS') {
        await _load();
      } else {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to load predictions. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final isTomorrow = _selectedDate != null && _selectedDate == _tomorrowDate;
    final canGenerate =
        widget.role == UserRole.bakeryManager &&
        isTomorrow &&
        _predictions.isEmpty &&
        !_generating &&
        !_loading;
    return Scaffold(
      appBar: AppBar(title: const Text('Demand Prediction')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                isTomorrow ? 'Next bakery date' : 'Selected bakery date',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                _selectedDate ?? (_loading ? 'Loading...' : 'Unavailable'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _tomorrowDate == null || _generating
                    ? null
                    : _chooseDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Choose date'),
              ),
              const SizedBox(height: 8),
              const Text('Saved predictions use the bakery date and context.'),
              if (_error != null) ...[
                const SizedBox(height: 16),
                BakeryNotice(_error!, kind: BakeryNoticeKind.error),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
              if (_loading || _generating) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (!_loading &&
                  _error == null &&
                  _selectedDate != null &&
                  _predictions.isEmpty) ...[
                const SizedBox(height: 24),
                const BakeryNotice(
                  'No prediction has been saved for this date.',
                ),
                if (widget.role == UserRole.bakeryManager && isTomorrow) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: canGenerate ? _generate : null,
                    icon: const Icon(Icons.auto_graph),
                    label: const Text('Generate Prediction'),
                  ),
                ],
              ],
              if (!_loading && _predictions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '${_predictions.length} saved categories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final prediction in _predictions)
                  _PredictionCard(prediction: prediction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.prediction});

  final DailyPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final factors = prediction.factors;
    final factorText = factors == null
        ? null
        : [
                ('Weekday', factors['weekdayFactor']),
                ('Monsoon', factors['monsoonFactor']),
                ('Weather', factors['weatherFactor']),
                ('Holiday', factors['holidayFactor']),
              ]
              .where((item) => item.$2 is num)
              .map((item) => '${item.$1} ${item.$2}')
              .join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prediction.breadCategoryName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${prediction.predictedUnitsSold} units',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              prediction.mode == PredictionMode.model
                  ? 'Random Forest model'
                  : 'Cold-start estimate',
            ),
            Text(
              prediction.mode == PredictionMode.model
                  ? '${prediction.confidenceLabel}: ${prediction.confidence!.toStringAsFixed(1)}%'
                  : prediction.confidenceLabel,
            ),
            if (factorText != null && factorText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(factorText),
            ],
            if (prediction.usedWeatherFallback ||
                prediction.usedCalendarFallback) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (prediction.usedWeatherFallback) 'Weather fallback used',
                  if (prediction.usedCalendarFallback) 'Calendar fallback used',
                ].join(' · '),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
