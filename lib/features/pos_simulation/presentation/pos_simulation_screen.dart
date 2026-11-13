import 'package:flutter/material.dart';

import '../../../core/theme/bakery_theme.dart';
import '../../../core/theme/bakery_widgets.dart';
import '../../../core/network/api_exception.dart';
import '../../inventory/data/recommendation_service.dart';
import '../../inventory/domain/recommendation_plan.dart';
import '../../profile/domain/user_profile.dart';
import '../data/pos_simulation_service.dart';
import '../domain/simulation_result.dart';

class PosSimulationScreen extends StatefulWidget {
  const PosSimulationScreen({
    required this.role,
    this.gateway,
    this.planningGateway,
    super.key,
  });

  final UserRole role;
  final PosSimulationGateway? gateway;
  final RecommendationGateway? planningGateway;

  @override
  State<PosSimulationScreen> createState() => _PosSimulationScreenState();
}

class _PosSimulationScreenState extends State<PosSimulationScreen> {
  late final PosSimulationGateway _gateway;
  late final RecommendationGateway _planningGateway;
  String? _date;
  String? _today;
  String? _error;
  String? _planningIssue;
  SimulationResult? _result;
  RecommendationPlan? _plan;
  bool _loading = true;
  bool _running = false;

  bool get _manager => widget.role == UserRole.bakeryManager;
  bool get _ready =>
      _manager &&
      _date == _today &&
      _result?.items.isEmpty == true &&
      _plan != null &&
      !_plan!.hasShortage &&
      _plan!.entries.isNotEmpty &&
      _plan!.entries.every((entry) => entry.state == PlanningState.confirmed);

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? PosSimulationService();
    _planningGateway = widget.planningGateway ?? RecommendationService();
    _load();
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as PosSimulationService).close();
    if (widget.planningGateway == null) {
      (_planningGateway as RecommendationService).close();
    }
    super.dispose();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to load POS simulation. Please try again.';
  }

  Future<void> _load([String? selectedDate]) async {
    setState(() {
      _loading = true;
      _error = null;
      _planningIssue = null;
    });
    try {
      final today = await _gateway.getBakeryToday();
      final date = selectedDate ?? _date ?? today;
      final result = await _gateway.getResult(date);
      RecommendationPlan? plan;
      String? issue;
      if (_manager && result.items.isEmpty) {
        try {
          plan = await _planningGateway.getPlan(date);
        } catch (error) {
          issue = _message(error);
        }
      }
      if (!mounted) return;
      setState(() {
        _today = today;
        _date = date;
        _result = result;
        _plan = plan;
        _planningIssue = issue;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDate() async {
    final today = _today;
    if (today == null || _loading || _running) return;
    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date ?? today),
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(today),
    );
    if (chosen == null || !mounted) return;
    await _load(chosen.toIso8601String().substring(0, 10));
  }

  Future<void> _run() async {
    final date = _date;
    if (date == null || !_ready || _running) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Run POS simulation?'),
        content: Text(
          'Run the confirmed production plan for $date using current '
          'weather at simulation time. Independent customer demand '
          'is generated before sales are limited by production. This '
          'deducts ingredients and saves results for every active category.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Run Simulation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await _gateway.run(date);
      if (!mounted) return;
      setState(() {
        _result = result;
        _plan = null;
      });
    } catch (error) {
      if (error is ApiException && error.code == 'ALREADY_SIMULATED') {
        await _load(date);
      } else if (mounted) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('POS Simulation')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(_date),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Simulation date',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _date ?? 'Loading...',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _loading || _running ? null : _chooseDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Choose another date'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const BakeryNotice(
                'Sales and financial figures are simulated, not real customer transactions.',
              ),
              if (_loading || _running) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _running
                      ? 'Checking current weather and saving simulation...'
                      : 'Loading simulation and production plan...',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                BakeryNotice(_error!, kind: BakeryNoticeKind.error),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _running
                        ? null
                        : _ready
                        ? _run
                        : () => _load(_date),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ],
              if (result != null && result.items.isNotEmpty) ...[
                BakerySectionHeader(
                  'Completed · ${result.items.length} categories',
                ),
                for (final item in result.items) _ResultCard(item: item),
              ] else if (!_loading && _manager) ...[
                const BakerySectionHeader('Production prerequisites'),
                if (_planningIssue != null)
                  BakeryNotice(_planningIssue!, kind: BakeryNoticeKind.warning),
                if (plan != null) ...[
                  if (plan.hasShortage)
                    const BakeryNotice(
                      'Confirmed quantities exceed valid ingredient stock.',
                      kind: BakeryNoticeKind.warning,
                    ),
                  for (final entry in plan.entries)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.breadCategoryName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              entry.state == PlanningState.confirmed
                                  ? '${entry.finalSelectedQty} units confirmed'
                                  : entry.state == PlanningState.processed
                                  ? 'Already processed'
                                  : 'Manager confirmation required',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                if (_date != _today)
                  const BakeryNotice(
                    'Past dates are view-only. A labelled historical scenario '
                    'is not available for a new simulation.',
                    kind: BakeryNoticeKind.info,
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _ready && !_running ? _run : null,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Run Simulation'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Every active category needs a stored prediction and manager '
                  'confirmation. Current weather describes the time of this '
                  'run, not the whole day. Demand adjustments are demo assumptions.',
                ),
              ] else if (!_loading) ...[
                const SizedBox(height: 16),
                const BakeryNotice('No completed simulation for this date.'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.item});
  final SimulationItem item;

  @override
  Widget build(BuildContext context) {
    final snapshot = item.simulationSnapshot;
    final baseline = snapshot?['baseline'];
    final weather = snapshot?['currentWeather'];
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.breadCategoryName, style: textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(switch (item.simulationMethod) {
              'INDEPENDENT_CURRENT_WEATHER_V3' =>
                'Independent baseline with current weather v3',
              'INDEPENDENT_BASELINE_V2' => 'Independent baseline scenario v2',
              _ => 'Legacy prediction-scaled scenario v1',
            }, style: textTheme.bodyMedium),
            const Divider(height: 28),
            Text('Demand and production', style: textTheme.titleMedium),
            const SizedBox(height: 10),
            _ResultValue('Predicted sales', '${item.predictedUnitsSold} units'),
            _ResultValue(
              'Simulated customer demand',
              '${item.simulatedDemand} units',
            ),
            _ResultValue('Production quantity', '${item.produced} units'),
            const Divider(height: 28),
            Text('Sales outcome', style: textTheme.titleMedium),
            const SizedBox(height: 10),
            _ResultValue('Units sold', '${item.unitsSold} units'),
            _ResultValue('Lost sales', '${item.lostSales} units'),
            _ResultValue('Leftover', '${item.leftover} units'),
            _ResultValue(
              'Unallocated leftover',
              '${item.remainingUnallocatedLeftover} units',
            ),
            const Divider(height: 28),
            Text(
              'Prediction and financial summary',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              item.predictionMode == 'MODEL'
                  ? 'Random Forest confidence ${item.confidence!.toStringAsFixed(1)}%'
                  : 'Cold-start heuristic · low confidence',
            ),
            const SizedBox(height: 10),
            _ResultValue(
              'Prediction error',
              '${item.salesPredictionError} units',
            ),
            _ResultValue('Revenue', 'RM ${item.revenue.toStringAsFixed(2)}'),
            _ResultValue(
              'Ingredient cost',
              'RM ${item.ingredientCost.toStringAsFixed(2)}',
            ),
            _ResultValue(
              'Gross profit',
              'RM ${item.grossProfit.toStringAsFixed(2)}',
            ),
            if (snapshot != null) ...[
              const Divider(height: 28),
              ExpansionTile(
                key: ValueKey('scenario-${item.breadCategoryName}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('Weather, holiday and scenario details'),
                children: [
                  _ResultValue(
                    'Baseline',
                    '${baseline is Map ? baseline['value'] : '—'} units',
                  ),
                  _ResultValue(
                    'Baseline source',
                    '${baseline is Map ? baseline['source'] : 'Unknown'}',
                  ),
                  _ResultValue(
                    'Scenario version',
                    '${snapshot['scenarioVersion']}',
                  ),
                  _ResultValue('Weather', '${snapshot['weatherCondition']}'),
                  _ResultValue(
                    'KL holiday',
                    snapshot['holiday'] == true ? 'Yes' : 'No',
                  ),
                  _ResultValue(
                    'Weekday factor',
                    '${snapshot['weekdayFactor']}',
                  ),
                  _ResultValue(
                    'Holiday factor',
                    '${snapshot['holidayFactor']}',
                  ),
                  _ResultValue(
                    'Weather factor',
                    '${snapshot['weatherFactor']}',
                  ),
                  _ResultValue(
                    'Random variation',
                    '${snapshot['variationPct']}%',
                  ),
                  if (weather is Map) ...[
                    _ResultValue(
                      'Current weather at simulation time',
                      '${weather['condition']}',
                    ),
                    _ResultValue(
                      'Observed (bakery time)',
                      _bakeryWeatherTime(weather['providerTimestamp']),
                    ),
                    const Text(
                      'This is weather at the time of the run, not the whole day.',
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultValue extends StatelessWidget {
  const _ResultValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: BakeryColors.secondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: BakeryColors.text),
        ),
      ],
    ),
  );
}

String _bakeryWeatherTime(Object? value) {
  final instant = value is String ? DateTime.tryParse(value) : null;
  if (instant == null) return 'Unavailable';
  final local = instant.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
