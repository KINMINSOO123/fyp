import 'package:flutter/material.dart';

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
          'Run the confirmed production plan for $date. This deducts ingredients and saves simulated sales and leftovers for every active category.',
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bakery date: ${_date ?? 'Loading...'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _chooseDate,
                    child: const Text('Change'),
                  ),
                ],
              ),
              const Text('Sales and financial figures are simulated.'),
              if (_loading || _running) const LinearProgressIndicator(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (result != null && result.items.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Completed · ${result.items.length} categories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final item in result.items) _ResultCard(item: item),
              ] else if (!_loading && _manager) ...[
                const SizedBox(height: 16),
                Text(
                  'Confirmed production',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_planningIssue != null) Text(_planningIssue!),
                if (plan != null) ...[
                  if (plan.hasShortage)
                    const Text(
                      'Confirmed quantities exceed valid ingredient stock.',
                    ),
                  for (final entry in plan.entries)
                    ListTile(
                      title: Text(entry.breadCategoryName),
                      subtitle: Text(
                        entry.state == PlanningState.confirmed
                            ? '${entry.finalSelectedQty} units confirmed'
                            : entry.state == PlanningState.processed
                            ? 'Already processed'
                            : 'Manager confirmation required',
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _ready && !_running ? _run : null,
                  child: const Text('Run Simulation'),
                ),
                const Text(
                  'Every active category needs a stored prediction and manager confirmation.',
                ),
              ] else if (!_loading) ...[
                const SizedBox(height: 16),
                const Text('No completed simulation for this date.'),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.breadCategoryName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Predicted ${item.predictedUnitsSold} · Produced ${item.produced}',
          ),
          Text(
            item.predictionMode == 'MODEL'
                ? 'Random Forest confidence ${item.confidence!.toStringAsFixed(1)}%'
                : 'Cold-start heuristic · low confidence',
          ),
          Text(
            'Sold ${item.unitsSold} · Lost sales ${item.lostSales} · Leftover ${item.leftover}',
          ),
          Text('Unallocated leftover: ${item.remainingUnallocatedLeftover}'),
          Text('Prediction error: ${item.salesPredictionError} units'),
          Text(
            'Revenue RM ${item.revenue.toStringAsFixed(2)} · Ingredient cost RM ${item.ingredientCost.toStringAsFixed(2)}',
          ),
          Text('Gross profit RM ${item.grossProfit.toStringAsFixed(2)}'),
        ],
      ),
    ),
  );
}
