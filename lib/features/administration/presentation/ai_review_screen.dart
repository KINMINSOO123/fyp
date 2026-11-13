import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/bakery_widgets.dart';
import '../data/ai_suggestions_service.dart';

String _requestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class _RecipeRow {
  _RecipeRow(AiRecipeIngredient draft)
    : name = TextEditingController(text: draft.name),
      grams = TextEditingController(text: '${draft.gramsPerBread}'),
      cost = TextEditingController(text: '0'),
      threshold = TextEditingController(text: '0');
  final TextEditingController name;
  final TextEditingController grams;
  final TextEditingController cost;
  final TextEditingController threshold;
  String? ingredientId;
  bool useExisting = false;
  bool confirmed = false;
  String unit = 'G';
  void dispose() {
    name.dispose();
    grams.dispose();
    cost.dispose();
    threshold.dispose();
  }
}

class AiReviewScreen extends StatefulWidget {
  const AiReviewScreen({required this.draft, this.reviewService, super.key});
  final AiBreadSuggestion draft;
  final AiReviewGateway? reviewService;
  @override
  State<AiReviewScreen> createState() => _AiReviewScreenState();
}

class _AiReviewScreenState extends State<AiReviewScreen> {
  late final AiReviewGateway _service;
  late String _id;
  String? _lastSubmittedBody;
  late final TextEditingController _name;
  late final TextEditingController _description;
  final _order = TextEditingController();
  final _shelfLife = TextEditingController(text: '24');
  final _price = TextEditingController(text: '0');
  late final List<_RecipeRow> _rows;
  List<Map<String, dynamic>> _ingredients = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.reviewService ?? AiReviewService();
    _id = _requestId();
    _name = TextEditingController(text: widget.draft.name);
    _description = TextEditingController(text: widget.draft.description);
    _rows = widget.draft.recipe.map(_RecipeRow.new).toList();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.catalogue();
      final ingredients = (data['ingredients'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final categories = (data['categories'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final row in _rows) {
        for (final item in ingredients) {
          if (item['isActive'] == true &&
              (item['name'] as String).trim().toLowerCase() ==
                  row.name.text.trim().toLowerCase()) {
            row.useExisting = true;
            row.ingredientId = item['id'] as String;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _ingredients = ingredients;
        _categories = categories;
        final maxOrder = categories.fold<int>(
          0,
          (max, category) => max > (category['displayOrder'] as int)
              ? max
              : category['displayOrder'] as int,
        );
        _order.text = '${maxOrder + 1}';
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is ApiException
              ? error.message
              : 'Unable to load the catalogue for review.';
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _order.dispose();
    _shelfLife.dispose();
    _price.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    if (widget.reviewService == null) (_service as AiReviewService).close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    final order = int.tryParse(_order.text.trim());
    final shelfLife = int.tryParse(_shelfLife.text.trim());
    final price = double.tryParse(_price.text.trim());
    if (_name.text.trim().isEmpty ||
        order == null ||
        shelfLife == null ||
        price == null ||
        _rows.isEmpty) {
      setState(() => _error = 'Complete the category and recipe fields.');
      return;
    }
    final recipe = <Map<String, dynamic>>[];
    for (final row in _rows) {
      final grams = double.tryParse(row.grams.text.trim());
      if (grams == null ||
          grams <= 0 ||
          (row.useExisting && row.ingredientId == null) ||
          (!row.useExisting &&
              (!row.confirmed ||
                  row.name.text.trim().isEmpty ||
                  double.tryParse(row.cost.text.trim()) == null ||
                  double.tryParse(row.threshold.text.trim()) == null))) {
        setState(
          () => _error = 'Check ingredient selection, grams and confirmations.',
        );
        return;
      }
      recipe.add({
        'ingredientId': row.useExisting ? row.ingredientId : null,
        'newIngredient': row.useExisting
            ? null
            : {
                'name': row.name.text.trim(),
                'unit': row.unit,
                'referenceUnitCost': double.parse(row.cost.text.trim()),
                'reorderThresholdGrams': double.parse(
                  row.threshold.text.trim(),
                ),
                'confirmed': row.confirmed,
              },
        'gramsPerUnit': grams,
      });
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add reviewed bread?'),
        content: const Text(
          'Create this category, its recipe and any confirmed '
          'new ingredients? New ingredients start with zero stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm and add'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'category': {
          'name': _name.text.trim(),
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          'displayOrder': order,
          'shelfLifeHours': shelfLife,
          'sellingPrice': price,
        },
        'recipe': recipe,
      };
      final encoded = jsonEncode(body);
      if (_lastSubmittedBody != null && _lastSubmittedBody != encoded) {
        _id = _requestId();
      }
      _lastSubmittedBody = encoded;
      await _service.create({'requestId': _id, ...body});
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to save the reviewed bread. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _ingredients
        .where((item) => item['isActive'] == true)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Review & Add Bread')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const BakeryNotice(
              'Review and trial bake this AI draft before use. '
              'Recipe amounts are grams per one bread, even if an ingredient '
              'reference unit is KG. No stock batches are created.',
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              BakeryNotice(_error!, kind: BakeryNoticeKind.error),
            ],
            const BakerySectionHeader('Bread category'),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _order,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Display order'),
            ),
            TextField(
              controller: _shelfLife,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Shelf life (hours)',
              ),
            ),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Selling price (MYR)',
              ),
            ),
            if (_categories.any(
              (item) =>
                  (item['name'] as String).trim().toLowerCase() ==
                  _name.text.trim().toLowerCase(),
            ))
              const BakeryNotice(
                'This category name already exists.',
                kind: BakeryNoticeKind.warning,
              ),
            const BakerySectionHeader('Recipe · grams per bread'),
            for (var index = 0; index < _rows.length; index++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ingredient ${index + 1}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove ingredient',
                            onPressed: _saving
                                ? null
                                : () => setState(
                                    () => _rows.removeAt(index).dispose(),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _rows[index].useExisting
                              ? 'Existing ingredient'
                              : 'Proposed new ingredient',
                        ),
                        value: _rows[index].useExisting,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() {
                                _rows[index].useExisting = value;
                                _rows[index].ingredientId = null;
                              }),
                      ),
                      if (_rows[index].useExisting)
                        DropdownButtonFormField<String>(
                          initialValue: _rows[index].ingredientId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Existing active ingredient',
                          ),
                          items: active
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item['id'] as String,
                                  child: Text(
                                    item['name'] as String,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _rows[index].ingredientId = value,
                                ),
                        )
                      else ...[
                        TextField(
                          controller: _rows[index].name,
                          decoration: const InputDecoration(
                            labelText: 'New ingredient name',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _rows[index].unit,
                          decoration: const InputDecoration(
                            labelText: 'Reference unit',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'G', child: Text('G')),
                            DropdownMenuItem(value: 'KG', child: Text('KG')),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _rows[index].unit = value ?? 'G',
                                ),
                        ),
                        TextField(
                          controller: _rows[index].cost,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Reference unit cost (MYR)',
                          ),
                        ),
                        TextField(
                          controller: _rows[index].threshold,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Reorder threshold (g)',
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('I confirm this new ingredient'),
                          value: _rows[index].confirmed,
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _rows[index].confirmed = value ?? false,
                                ),
                        ),
                      ],
                      TextField(
                        controller: _rows[index].grams,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Grams per bread',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: _saving || _rows.length >= 15
                  ? null
                  : () => setState(
                      () => _rows.add(
                        _RecipeRow(
                          const AiRecipeIngredient(
                            name: '',
                            gramsPerBread: 0,
                            availability: 'NOT_IN_INVENTORY',
                            availableGrams: 0,
                          ),
                        ),
                      ),
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Add ingredient'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  _saving || _loading || _error != null && _ingredients.isEmpty
                  ? null
                  : _save,
              child: Text(_saving ? 'Saving...' : 'Confirm and add bread'),
            ),
            if (_saving) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
