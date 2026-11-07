import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/model_management_service.dart';
import '../domain/model_review.dart';

class ModelDetailScreen extends StatefulWidget {
  const ModelDetailScreen({
    required this.modelId,
    required this.gateway,
    super.key,
  });
  final String modelId;
  final ModelManagementGateway gateway;

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen> {
  ModelVersionReview? _model;
  List<ModelVersionReview> _categoryModels = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to load model details. Please try again.';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _model = null;
      _categoryModels = [];
    });
    try {
      final model = await widget.gateway.getModel(widget.modelId);
      final versions = <ModelVersionReview>[];
      var pageNumber = 1;
      while (true) {
        final page = await widget.gateway.listModels(
          breadCategoryId: model.breadCategoryId,
          page: pageNumber,
        );
        versions.addAll(page.items);
        if (pageNumber * page.pageSize >= page.total) break;
        pageNumber++;
      }
      if (!mounted) return;
      setState(() {
        _model = model;
        _categoryModels = versions;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ModelVersionReview? _matching(
    ModelVersionReview model,
    bool Function(ModelVersionReview) predicate,
  ) {
    final candidateEval = model.latestEvaluation;
    if (candidateEval == null) return null;
    for (final version in _categoryModels) {
      final evaluation = version.latestEvaluation;
      if (predicate(version) &&
          evaluation != null &&
          evaluation.holdoutFingerprint == candidateEval.holdoutFingerprint &&
          evaluation.holdoutStart == candidateEval.holdoutStart &&
          evaluation.holdoutEnd == candidateEval.holdoutEnd) {
        return version;
      }
    }
    return null;
  }

  ModelVersionReview? _activeFor(ModelVersionReview model) {
    for (final item in _categoryModels) {
      if (item.breadCategoryId == model.breadCategoryId &&
          item.modelType == ModelType.randomForest &&
          item.lifecycleStatus == ModelStatus.active) {
        return item;
      }
    }
    return null;
  }

  Future<bool> _confirm(String title, String description, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _metric(double? value, {String suffix = ''}) =>
      value == null ? 'Not Applicable' : '${value.toStringAsFixed(2)}$suffix';

  Widget _metrics(String label, ModelEvaluationReview evaluation) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'MAE ${_metric(evaluation.mae)} · RMSE ${_metric(evaluation.rmse)}',
            ),
            Text(
              'MAPE ${_metric(evaluation.mape, suffix: '%')} · R² ${_metric(evaluation.rSquared)}',
            ),
            Text(
              'Test: ${evaluation.holdoutStart} to ${evaluation.holdoutEnd} · ${evaluation.sampleCount} days',
            ),
            Text('MAPE sample: ${evaluation.mapeSampleCount} nonzero actuals'),
            Text('Origin: ${evaluation.evaluationLabel}'),
            Text(evaluation.dataOrigins.join(', ')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final active = model == null ? null : _activeFor(model);
    final comparableActive = model == null || active == null
        ? null
        : _matching(model, (item) => item.id == active.id);
    final baseline = model == null
        ? null
        : _matching(
            model,
            (item) =>
                item.modelType == ModelType.linearRegression &&
                item.trainingGroupId != null &&
                item.trainingGroupId == model.trainingGroupId,
          );
    final evaluation = model?.latestEvaluation;
    final canActivate =
        model != null &&
        model.isRandomForestCandidate &&
        evaluation != null &&
        (active == null ||
            (comparableActive != null &&
                evaluation.mae <= comparableActive.latestEvaluation!.mae));
    return Scaffold(
      appBar: AppBar(title: const Text('Model Version')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading || _busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _loading || _busy ? null : _load,
                  child: const Text('Retry'),
                ),
              ],
              if (model != null) ...[
                Text(
                  '${model.breadCategoryName} · v${model.version}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${model.modelType == ModelType.randomForest ? 'Random Forest' : 'Linear Regression'} · ${model.lifecycleStatus.name.toUpperCase()}',
                ),
                Text(
                  'Training: ${model.trainingStart} to ${model.trainingEnd}',
                ),
                if (model.holdoutStart != null)
                  Text('Reserved test period starts ${model.holdoutStart}'),
                const SizedBox(height: 12),
                if (evaluation == null)
                  const Text('No saved evaluation for this version.')
                else ...[
                  _metrics('Selected version', evaluation),
                  if (baseline?.latestEvaluation != null)
                    _metrics(
                      'Linear Regression baseline · same test set',
                      baseline!.latestEvaluation!,
                    ),
                  if (comparableActive?.latestEvaluation != null)
                    _metrics(
                      'Current active Random Forest · same test set',
                      comparableActive!.latestEvaluation!,
                    ),
                  if (active != null &&
                      comparableActive == null &&
                      model.isRandomForestCandidate)
                    const Text(
                      'The current active model has no latest evaluation on this test set. Evaluate this candidate again before activation.',
                    ),
                ],
                if (model.trainingOriginCounts != null)
                  Text('Training origins: ${model.trainingOriginCounts}'),
                if (model.holdoutOriginCounts != null)
                  Text('Initial holdout origins: ${model.holdoutOriginCounts}'),
                const SizedBox(height: 16),
                if (model.isRandomForestCandidate) ...[
                  FilledButton.icon(
                    onPressed: _loading || _busy
                        ? null
                        : () => _run(
                            () => widget.gateway.evaluate(model.id),
                            'Evaluation saved. Review the common test set.',
                          ),
                    icon: const Icon(Icons.assessment_outlined),
                    label: const Text('Evaluate Candidate'),
                  ),
                  FilledButton.icon(
                    onPressed: !_loading && !_busy && canActivate
                        ? () async {
                            final description = active == null
                                ? 'Activate this first Random Forest model with MAE ${_metric(evaluation.mae)} on ${evaluation.holdoutStart} to ${evaluation.holdoutEnd}?'
                                : 'Candidate MAE ${_metric(evaluation.mae)} versus active MAE ${_metric(comparableActive!.latestEvaluation!.mae)} on the same test set (${evaluation.holdoutStart} to ${evaluation.holdoutEnd}). Activate this candidate?';
                            if (!await _confirm(
                                  'Activate candidate?',
                                  description,
                                  'Activate',
                                ) ||
                                !mounted) {
                              return;
                            }
                            await _run(
                              () => widget.gateway.activate(
                                model.id,
                                evaluation.id,
                              ),
                              'Candidate activated.',
                            );
                          }
                        : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Activate Candidate'),
                  ),
                  if (evaluation != null &&
                      active != null &&
                      comparableActive != null &&
                      evaluation.mae > comparableActive.latestEvaluation!.mae)
                    const Text(
                      'Activation blocked: candidate MAE is higher than the active model on the same test set.',
                    ),
                ],
                if (model.isRestorableType)
                  FilledButton.icon(
                    onPressed: _loading || _busy
                        ? null
                        : () async {
                            if (!await _confirm(
                                  'Restore model?',
                                  'Restore this retained Random Forest version? The server will recheck its artifact, evaluation and current active version.',
                                  'Restore',
                                ) ||
                                !mounted) {
                              return;
                            }
                            await _run(
                              () => widget.gateway.restore(model.id),
                              'Previous model restored.',
                            );
                          },
                    icon: const Icon(Icons.history),
                    label: const Text('Restore Previous Model'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
