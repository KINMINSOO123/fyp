import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/model_management_service.dart';
import '../domain/model_review.dart';
import 'model_detail_screen.dart';

class ModelListScreen extends StatefulWidget {
  const ModelListScreen({this.gateway, super.key});
  final ModelManagementGateway? gateway;

  @override
  State<ModelListScreen> createState() => _ModelListScreenState();
}

class _ModelListScreenState extends State<ModelListScreen> {
  late final ModelManagementGateway _gateway;
  List<TrainingCategory> _categories = [];
  ModelReviewPage? _page;
  String? _categoryId;
  String? _error;
  bool _loading = true;
  bool _training = false;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? ModelManagementService();
    _load(1, withCategories: true);
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as ModelManagementService).close();
    super.dispose();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to load model versions. Please try again.';
  }

  Future<void> _load(int page, {bool withCategories = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = withCategories
          ? await _gateway.listCategories()
          : _categories;
      final result = await _gateway.listModels(
        breadCategoryId: _categoryId,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _page = result;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _train() async {
    final selected = _categories
        .where((item) => item.id == _categoryId)
        .firstOrNull;
    if (selected == null || _training) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Train candidate models?'),
        content: Text(
          'Train Random Forest and Linear Regression candidates for ${selected.name}. Training does not activate either model.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Train'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _training = true;
      _error = null;
    });
    try {
      await _gateway.train(selected.id);
      if (!mounted) return;
      await _load(1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Candidate models saved. Evaluate the Random Forest candidate before activation.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _training = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: const Text('Model Management')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButton<String?>(
                    value: _categoryId,
                    isExpanded: true,
                    hint: const Text('All categories'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All categories'),
                      ),
                      for (final category in _categories)
                        DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: _loading || _training
                        ? null
                        : (value) {
                            setState(() {
                              _categoryId = value;
                              _page = null;
                            });
                            _load(1);
                          },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _categoryId != null && !_loading && !_training
                        ? _train
                        : null,
                    icon: const Icon(Icons.model_training),
                    label: const Text('Train Candidates'),
                  ),
                  const Text(
                    'Select an active category. At least 30 validated sales days are required.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => _load(page?.page ?? 1, withCategories: true),
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
            if (_loading || _training) const LinearProgressIndicator(),
            Expanded(
              child: page == null
                  ? Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : const Text('Model history is unavailable.'),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(page.page, withCategories: true),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: page.items.isEmpty ? 1 : page.items.length,
                        itemBuilder: (context, index) {
                          if (page.items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No model versions for this selection.',
                              ),
                            );
                          }
                          final model = page.items[index];
                          return Card(
                            child: ListTile(
                              title: Text(
                                '${model.breadCategoryName} · v${model.version}',
                              ),
                              subtitle: Text(
                                '${model.modelType == ModelType.randomForest ? 'Random Forest' : 'Linear Regression'} · ${model.lifecycleStatus.name.toUpperCase()}\n'
                                'Trained ${model.trainingStart} to ${model.trainingEnd}'
                                '${model.latestEvaluation == null ? '' : '\nLatest MAE ${model.latestEvaluation!.mae.toStringAsFixed(2)} · ${model.latestEvaluation!.evaluationLabel}'}',
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ModelDetailScreen(
                                      modelId: model.id,
                                      gateway: _gateway,
                                    ),
                                  ),
                                );
                                if (mounted) await _load(page.page);
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),
            if (page != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: page.page > 1 && !_loading
                          ? () => _load(page.page - 1)
                          : null,
                      child: const Text('Previous'),
                    ),
                    Expanded(
                      child: Text(
                        'Page ${page.page} · ${page.total} versions',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    OutlinedButton(
                      onPressed:
                          page.page * page.pageSize < page.total && !_loading
                          ? () => _load(page.page + 1)
                          : null,
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
