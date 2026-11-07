import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../prediction/data/prediction_service.dart';
import '../data/recommendation_service.dart';
import '../domain/recommendation_plan.dart';

class ProductionPlanningScreen extends StatefulWidget {
  const ProductionPlanningScreen({
    this.gateway,
    this.predictionGateway,
    super.key,
  });
  final RecommendationGateway? gateway;
  final PredictionGateway? predictionGateway;

  @override
  State<ProductionPlanningScreen> createState() =>
      _ProductionPlanningScreenState();
}

class _ProductionPlanningScreenState extends State<ProductionPlanningScreen> {
  late final RecommendationGateway _gateway;
  late final PredictionGateway _predictionGateway;
  RecommendationPlan? _plan;
  String? _date;
  String? _error;
  bool _missingPrediction = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? RecommendationService();
    _predictionGateway = widget.predictionGateway ?? PredictionService();
    _load();
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as RecommendationService).close();
    if (widget.predictionGateway == null) {
      (_predictionGateway as PredictionService).close();
    }
    super.dispose();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to load production planning. Please try again.';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _plan = null;
      _date = null;
      _missingPrediction = false;
    });
    try {
      final next = await _predictionGateway.getNextDayState();
      final plan = next.predictions.isEmpty
          ? null
          : await _gateway.getPlan(next.targetDate);
      if (!mounted) return;
      setState(() {
        _date = next.targetDate;
        _missingPrediction = plan == null;
        _plan = plan;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(RecommendationEntry entry) async {
    final date = _date;
    if (date == null || _busy || entry.state == PlanningState.processed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await _gateway.getPlan(
        date,
        revisingPredictionId: entry.state == PlanningState.confirmed
            ? entry.predictionId
            : null,
      );
      if (!mounted) return;
      if (preview.hasShortage) {
        setState(
          () => _error =
              'Existing commitments exceed valid stock. Revise or restock first.',
        );
        return;
      }
      final current = preview.entries
          .where((item) => item.predictionId == entry.predictionId)
          .firstOrNull;
      if (current?.recommendedProduction == null) {
        setState(() => _error = 'A current recommendation is unavailable.');
        return;
      }
      final saved = await Navigator.of(context).push<RecommendationPlan>(
        MaterialPageRoute(
          builder: (_) => _DecisionEditor(
            entry: current!,
            revising: entry.state == PlanningState.confirmed,
            gateway: _gateway,
          ),
        ),
      );
      if (mounted && saved != null) setState(() => _plan = saved);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Production Planning')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Next bakery date: ${_date ?? (_loading ? 'Loading...' : 'Unavailable')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text('Confirming a plan does not deduct inventory.'),
              if (_loading || _busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Retry'),
                ),
              ],
              if (_missingPrediction && !_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                    'Generate and save the next-day prediction before planning production.',
                  ),
                ),
              if (plan != null) ...[
                if (plan.hasShortage) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Confirmed commitments exceed valid stock. No new recommendation is available.',
                  ),
                  for (final shortage in plan.shortages)
                    Text(
                      '${shortage.name}: ${shortage.shortageGrams.toStringAsFixed(3)} g short',
                    ),
                ],
                const SizedBox(height: 12),
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
                          Text(
                            'Predicted sales: ${entry.predictedUnitsSold} units',
                          ),
                          Text(
                            entry.predictionMode == 'COLD_START'
                                ? 'Cold-start · Low-confidence heuristic estimate'
                                : '${entry.lowConfidence ? 'Low Confidence' : 'Model agreement'}: ${entry.confidence!.toStringAsFixed(1)}%',
                          ),
                          Text(
                            'Recommended: ${entry.recommendedProduction?.toString() ?? 'Unavailable'} units',
                          ),
                          if (entry.maxProducible != null)
                            Text(
                              'Maximum at this planning step: ${entry.maxProducible} units',
                            ),
                          if (entry.finalSelectedQty != null)
                            Text('Confirmed: ${entry.finalSelectedQty} units'),
                          Text('Status: ${entry.state.name.toUpperCase()}'),
                          const SizedBox(height: 6),
                          for (final ingredient in entry.ingredientRequirements)
                            Text(
                              '${ingredient.name}: ${ingredient.gramsPerUnit.toStringAsFixed(3)} g/unit',
                            ),
                          if (!plan.hasShortage &&
                              entry.state != PlanningState.processed)
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: _busy ? null : () => _edit(entry),
                                child: Text(
                                  entry.state == PlanningState.confirmed
                                      ? 'Revise Decision'
                                      : 'Confirm Production',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionEditor extends StatefulWidget {
  const _DecisionEditor({
    required this.entry,
    required this.revising,
    required this.gateway,
  });
  final RecommendationEntry entry;
  final bool revising;
  final RecommendationGateway gateway;

  @override
  State<_DecisionEditor> createState() => _DecisionEditorState();
}

class _DecisionEditorState extends State<_DecisionEditor> {
  late final TextEditingController _quantity = TextEditingController(
    text: widget.entry.recommendedProduction.toString(),
  );
  final TextEditingController _reason = TextEditingController();
  String _option = 'ACCEPT_RECOMMENDATION';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final recommended = widget.entry.recommendedProduction!;
    final selected = _option == 'ACCEPT_RECOMMENDATION'
        ? recommended
        : int.tryParse(_quantity.text.trim());
    final reason = _option == 'ACCEPT_RECOMMENDATION'
        ? null
        : _reason.text.trim();
    if (selected == null ||
        selected < 0 ||
        (_option == 'REDUCE' && selected >= recommended) ||
        (_option != 'ACCEPT_RECOMMENDATION' &&
            (reason == null || reason.isEmpty))) {
      setState(
        () =>
            _error = 'Enter a valid whole quantity and reason for this option.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.gateway.confirm(
        predictionId: widget.entry.predictionId,
        finalSelectedQty: selected,
        selectedOption: _option,
        decisionReason: reason,
      );
      if (mounted) Navigator.pop(context, updated);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to save the decision. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.revising ? 'Revise Decision' : 'Confirm Production'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.entry.breadCategoryName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            'Current recommendation: ${widget.entry.recommendedProduction} units',
          ),
          Text('Sequential maximum: ${widget.entry.maxProducible} units'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _option,
            decoration: const InputDecoration(labelText: 'Decision'),
            items: const [
              DropdownMenuItem(
                value: 'ACCEPT_RECOMMENDATION',
                child: Text('Accept recommendation'),
              ),
              DropdownMenuItem(value: 'REDUCE', child: Text('Reduce quantity')),
              DropdownMenuItem(
                value: 'MANUAL_OVERRIDE',
                child: Text('Manual override'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _option = value!),
          ),
          const SizedBox(height: 12),
          if (_option != 'ACCEPT_RECOMMENDATION') ...[
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Selected whole units',
              ),
            ),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
          if (_option == 'MANUAL_OVERRIDE')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'An override may redistribute unconfirmed recommendations. The server checks all confirmed commitments and valid stock.',
              ),
            ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_saving) const Center(child: CircularProgressIndicator()),
          FilledButton(
            key: const Key('save-production-decision'),
            onPressed: _saving ? null : _save,
            child: Text(
              widget.revising ? 'Save Revision' : 'Confirm Production',
            ),
          ),
        ],
      ),
    ),
  );
}
