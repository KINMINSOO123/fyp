import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
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
  NextPredictionState? _state;
  String? _error;
  bool _loading = true;
  bool _generating = false;

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
    setState(() {
      _loading = true;
      _error = null;
      _state = null;
    });
    try {
      final state = await _gateway.getNextDayState();
      if (!mounted) return;
      setState(() => _state = state);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_generating ||
        _loading ||
        widget.role != UserRole.bakeryManager ||
        _state == null ||
        _state!.predictions.isNotEmpty) {
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
    final state = _state;
    final canGenerate =
        widget.role == UserRole.bakeryManager &&
        state != null &&
        state.predictions.isEmpty &&
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
                'Next bakery date',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                state?.targetDate ?? (_loading ? 'Loading...' : 'Unavailable'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Predictions use the bakery date and saved context.'),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
              if (_loading || _generating) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (!_loading && state != null && state.predictions.isEmpty) ...[
                const SizedBox(height: 24),
                const Text('No prediction has been saved for this date.'),
                if (widget.role == UserRole.bakeryManager) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: canGenerate ? _generate : null,
                    icon: const Icon(Icons.auto_graph),
                    label: const Text('Generate Prediction'),
                  ),
                ],
              ],
              if (state != null && state.predictions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '${state.predictions.length} saved categories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final prediction in state.predictions)
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
