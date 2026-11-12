import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/inventory_admin_service.dart';
import 'dialog_controller_scope.dart';
import 'restock_admin_screen.dart';

class InventoryAdminScreen extends StatefulWidget {
  const InventoryAdminScreen({this.gateway, super.key});
  final InventoryAdminGateway? gateway;

  @override
  State<InventoryAdminScreen> createState() => _InventoryAdminScreenState();
}

class _InventoryAdminScreenState extends State<InventoryAdminScreen> {
  late final InventoryAdminGateway _gateway;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _ingredients = [];
  List<Map<String, dynamic>> _batches = [];
  int _batchPage = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? InventoryAdminService();
    _load();
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as InventoryAdminService).close();
    super.dispose();
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : error is FormatException
      ? error.message
      : 'Unable to save or load inventory. Please try again.';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await _gateway.categories();
      final ingredients = await _gateway.ingredients();
      final batches = await _gateway.batches(_batchPage);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _ingredients = ingredients;
        _batches = batches;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _scanAlerts() async {
    try {
      final count = await _gateway.scanAlerts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$count stock or expiry alert conditions detected. '
            'Duplicate recipient events are ignored.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _categoryDialog([Map<String, dynamic>? existing]) async {
    final name = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final description = TextEditingController(
      text: existing?['description'] as String? ?? '',
    );
    final order = TextEditingController(
      text: '${existing?['displayOrder'] ?? _categories.length + 1}',
    );
    final shelfLife = TextEditingController(
      text: '${existing?['shelfLifeHours'] ?? 24}',
    );
    final price = TextEditingController(
      text: '${existing?['sellingPrice'] ?? 0}',
    );
    var active = existing?['isActive'] == true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(
            existing == null ? 'Add bread category' : 'Edit bread category',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Display order'),
                ),
                TextField(
                  controller: shelfLife,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Shelf life (hours)',
                  ),
                ),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Selling price (MYR)',
                  ),
                ),
                SwitchListTile(
                  title: const Text('Active'),
                  value: active,
                  onChanged: existing == null
                      ? null
                      : (value) => refresh(() => active = value),
                ),
                if (existing == null)
                  const Text('Create inactive, add a recipe, then activate.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final displayOrder = int.tryParse(order.text);
                final hours = int.tryParse(shelfLife.text);
                final sellingPrice = double.tryParse(price.text);
                if (displayOrder == null ||
                    hours == null ||
                    sellingPrice == null ||
                    name.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter valid category fields.'),
                    ),
                  );
                  return;
                }
                _save(
                  () => _gateway.saveCategory({
                    'name': name.text.trim(),
                    'description': description.text.trim().isEmpty
                        ? null
                        : description.text.trim(),
                    'displayOrder': displayOrder,
                    'shelfLifeHours': hours,
                    'sellingPrice': sellingPrice,
                    'isActive': active,
                  }, id: existing?['id'] as String?),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    order.dispose();
    shelfLife.dispose();
    price.dispose();
  }

  Future<void> _ingredientDialog([Map<String, dynamic>? existing]) async {
    final name = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final cost = TextEditingController(
      text: '${existing?['referenceUnitCost'] ?? 0}',
    );
    final threshold = TextEditingController(
      text: '${existing?['reorderThresholdGrams'] ?? 0}',
    );
    var unit = existing?['unit'] as String? ?? 'KG';
    var active = existing?['isActive'] as bool? ?? true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(existing == null ? 'Add ingredient' : 'Edit ingredient'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  items: const [
                    DropdownMenuItem(value: 'KG', child: Text('KG')),
                    DropdownMenuItem(value: 'G', child: Text('G')),
                  ],
                  onChanged: (value) => refresh(() => unit = value ?? unit),
                  decoration: const InputDecoration(
                    labelText: 'Reference unit',
                  ),
                ),
                TextField(
                  controller: cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Reference unit cost (MYR)',
                  ),
                ),
                TextField(
                  controller: threshold,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Reorder threshold (g)',
                  ),
                ),
                SwitchListTile(
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => refresh(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final referenceCost = double.tryParse(cost.text);
                final reorder = double.tryParse(threshold.text);
                if (name.text.trim().isEmpty ||
                    referenceCost == null ||
                    reorder == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter valid ingredient fields.'),
                    ),
                  );
                  return;
                }
                _save(
                  () => _gateway.saveIngredient({
                    'name': name.text.trim(),
                    'unit': unit,
                    'referenceUnitCost': referenceCost,
                    'reorderThresholdGrams': reorder,
                    'isActive': active,
                  }, id: existing?['id'] as String?),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    cost.dispose();
    threshold.dispose();
  }

  Future<void> _recipeDialog(Map<String, dynamic> category) async {
    try {
      final current = await _gateway.recipe(category['id'] as String);
      if (!mounted) return;
      final result = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (_) => _RecipeDialog(
          categoryName: category['name'] as String,
          ingredients: _ingredients,
          current: current,
        ),
      );
      if (result == null) return;
      await _gateway.replaceRecipe(category['id'] as String, result);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _receiptDialog() async {
    if (_ingredients.where((item) => item['isActive'] == true).isEmpty) return;
    String? ingredientId =
        _ingredients.firstWhere((item) => item['isActive'] == true)['id']
            as String;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final received = TextEditingController(text: today);
    final expiry = TextEditingController();
    final quantity = TextEditingController();
    final unitCost = TextEditingController();
    final source = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => DialogControllerScope(
        controllers: [received, expiry, quantity, unitCost, source],
        child: StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('Receive ingredient batch'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: ingredientId,
                    items: _ingredients
                        .where((item) => item['isActive'] == true)
                        .map(
                          (item) => DropdownMenuItem(
                            value: item['id'] as String,
                            child: Text(item['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => refresh(() => ingredientId = value),
                    decoration: const InputDecoration(labelText: 'Ingredient'),
                  ),
                  TextField(
                    controller: received,
                    decoration: const InputDecoration(
                      labelText: 'Received date (YYYY-MM-DD)',
                    ),
                  ),
                  TextField(
                    controller: expiry,
                    decoration: const InputDecoration(
                      labelText: 'Expiry date (YYYY-MM-DD)',
                    ),
                  ),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity (g)',
                    ),
                  ),
                  TextField(
                    controller: unitCost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Batch cost (MYR/kg)',
                    ),
                  ),
                  TextField(
                    controller: source,
                    decoration: const InputDecoration(
                      labelText: 'Supplier/source (optional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final grams = double.tryParse(quantity.text);
                  final cost = double.tryParse(unitCost.text);
                  if (grams == null ||
                      cost == null ||
                      expiry.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter valid receipt fields.'),
                      ),
                    );
                    return;
                  }
                  _save(
                    () => _gateway.receiveBatch({
                      'ingredientId': ingredientId,
                      'receivedDate': received.text.trim(),
                      'expiryDate': expiry.text.trim(),
                      'quantityGrams': grams,
                      'unitCostSnapshot': cost,
                      'source': source.text.trim().isEmpty
                          ? null
                          : source.text.trim(),
                    }),
                  );
                },
                child: const Text('Receive'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeDialog(Map<String, dynamic> batch) async {
    final grams = TextEditingController();
    final note = TextEditingController();
    var reason = 'DISCARD';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Remove batch stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Remaining: ${batch['remainingQuantityGrams']} g'),
              TextField(
                controller: grams,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Remove (g)'),
              ),
              DropdownButtonFormField<String>(
                initialValue: reason,
                items: const [
                  DropdownMenuItem(value: 'DISCARD', child: Text('Discard')),
                  DropdownMenuItem(
                    value: 'CORRECTION',
                    child: Text('Stock correction'),
                  ),
                ],
                onChanged: (value) => refresh(() => reason = value ?? reason),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Reason/note'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final removed = double.tryParse(grams.text);
                if (removed == null ||
                    removed <= 0 ||
                    note.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a positive amount and reason.'),
                    ),
                  );
                  return;
                }
                _save(
                  () => _gateway.removeBatchStock(batch['id'] as String, {
                    'removedGrams': removed,
                    'reason': reason,
                    'note': note.text.trim(),
                  }),
                );
              },
              child: const Text('Confirm removal'),
            ),
          ],
        ),
      ),
    );
    grams.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Administration'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Categories'),
            Tab(text: 'Ingredients'),
            Tab(text: 'Batches'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RestockAdminScreen(),
              ),
            ),
            icon: const Icon(Icons.local_shipping_outlined),
            tooltip: 'Restock requests',
          ),
          IconButton(
            onPressed: _scanAlerts,
            icon: const Icon(Icons.notification_add_outlined),
            tooltip: 'Check stock and expiry alerts',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : TabBarView(
              children: [
                ListView(
                  children: [
                    ListTile(
                      title: const Text('Bread categories'),
                      subtitle: const Text(
                        'Create inactive, add a recipe, then activate.',
                      ),
                      trailing: IconButton(
                        onPressed: () => _categoryDialog(),
                        icon: const Icon(Icons.add),
                        tooltip: 'Add category',
                      ),
                    ),
                    for (final category in _categories)
                      Card(
                        child: ListTile(
                          title: Text(category['name'] as String),
                          subtitle: Text(
                            'Order ${category['displayOrder']} · ${category['isActive'] == true ? 'Active' : 'Inactive'} · MYR ${category['sellingPrice']}',
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                onPressed: () => _recipeDialog(category),
                                icon: const Icon(Icons.receipt_long),
                                tooltip: 'Edit recipe',
                              ),
                              IconButton(
                                onPressed: () => _categoryDialog(category),
                                icon: const Icon(Icons.edit),
                                tooltip: 'Edit category',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                ListView(
                  children: [
                    ListTile(
                      title: const Text('Ingredients and stock'),
                      trailing: IconButton(
                        onPressed: () => _ingredientDialog(),
                        icon: const Icon(Icons.add),
                        tooltip: 'Add ingredient',
                      ),
                    ),
                    for (final ingredient in _ingredients)
                      Card(
                        child: ListTile(
                          title: Text(ingredient['name'] as String),
                          subtitle: Text(
                            '${ingredient['snapshotQuantityGrams']} g · ${ingredient['isActive'] == true ? 'Active' : 'Inactive'}',
                          ),
                          trailing: IconButton(
                            onPressed: () => _ingredientDialog(ingredient),
                            icon: const Icon(Icons.edit),
                            tooltip: 'Edit ingredient',
                          ),
                        ),
                      ),
                  ],
                ),
                ListView(
                  children: [
                    ListTile(
                      title: const Text('Batch receipts and adjustments'),
                      subtitle: const Text(
                        'Production later consumes valid batches by FEFO.',
                      ),
                      trailing: IconButton(
                        onPressed: _receiptDialog,
                        icon: const Icon(Icons.add),
                        tooltip: 'Receive batch',
                      ),
                    ),
                    for (final batch in _batches)
                      Card(
                        child: ListTile(
                          title: Text(
                            _ingredients
                                    .where(
                                      (item) =>
                                          item['id'] == batch['ingredientId'],
                                    )
                                    .map((item) => item['name'] as String)
                                    .firstOrNull ??
                                'Ingredient',
                          ),
                          subtitle: Text(
                            'Received ${batch['receivedDate']} · expires ${batch['expiryDate']}\n${batch['remainingQuantityGrams']} g · ${batch['status']} · MYR ${batch['unitCostSnapshot']}/kg',
                          ),
                          isThreeLine: true,
                          trailing: batch['status'] == 'ACTIVE'
                              ? IconButton(
                                  onPressed: () => _removeDialog(batch),
                                  icon: const Icon(Icons.remove_circle_outline),
                                  tooltip: 'Remove batch stock',
                                )
                              : null,
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _batchPage <= 1
                              ? null
                              : () {
                                  _batchPage--;
                                  _load();
                                },
                          child: const Text('Previous'),
                        ),
                        Text('Page $_batchPage'),
                        TextButton(
                          onPressed: _batches.length < 50
                              ? null
                              : () {
                                  _batchPage++;
                                  _load();
                                },
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
    ),
  );
}

class _RecipeDialog extends StatefulWidget {
  const _RecipeDialog({
    required this.categoryName,
    required this.ingredients,
    required this.current,
  });
  final String categoryName;
  final List<Map<String, dynamic>> ingredients;
  final List<Map<String, dynamic>> current;

  @override
  State<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<_RecipeDialog> {
  final List<String?> _ids = [];
  final List<TextEditingController> _grams = [];

  @override
  void initState() {
    super.initState();
    for (final row in widget.current) {
      _ids.add(row['ingredientId'] as String);
      _grams.add(TextEditingController(text: '${row['gramsPerUnit']}'));
    }
  }

  @override
  void dispose() {
    for (final controller in _grams) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.categoryName} recipe'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < _ids.length; index++)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _ids[index],
                      items: widget.ingredients
                          .map(
                            (item) => DropdownMenuItem(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _ids[index] = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 85,
                    child: TextField(
                      controller: _grams[index],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'g/unit'),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _ids.removeAt(index);
                      _grams.removeAt(index).dispose();
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove ingredient',
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () => setState(() {
                _ids.add(null);
                _grams.add(TextEditingController());
              }),
              icon: const Icon(Icons.add),
              label: const Text('Add ingredient'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final items = <Map<String, dynamic>>[];
          for (var index = 0; index < _ids.length; index++) {
            final grams = double.tryParse(_grams[index].text);
            if (_ids[index] == null || grams == null || grams <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Choose an ingredient and positive grams per unit.',
                  ),
                ),
              );
              return;
            }
            items.add({'ingredientId': _ids[index], 'gramsPerUnit': grams});
          }
          if (items.isEmpty ||
              items.map((item) => item['ingredientId']).toSet().length !=
                  items.length) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Add at least one unique ingredient.'),
              ),
            );
            return;
          }
          Navigator.pop(context, items);
        },
        child: const Text('Save recipe'),
      ),
    ],
  );
}
