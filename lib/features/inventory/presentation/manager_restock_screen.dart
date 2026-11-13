import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../data/inventory_admin_service.dart';

String _receiptKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ManagerRestockScreen extends StatefulWidget {
  const ManagerRestockScreen({
    this.ingredientId,
    this.suggestedGrams,
    this.gateway,
    super.key,
  });
  final String? ingredientId;
  final num? suggestedGrams;
  final InventoryAdminGateway? gateway;
  @override
  State<ManagerRestockScreen> createState() => _ManagerRestockScreenState();
}

class _ManagerRestockScreenState extends State<ManagerRestockScreen> {
  late final InventoryAdminGateway _gateway;
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _received = TextEditingController();
  final _expiry = TextEditingController();
  final _source = TextEditingController();
  late String _key;
  List<Map<String, dynamic>> _ingredients = [];
  String? _ingredientId;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? InventoryAdminService();
    _key = _receiptKey();
    _received.text = DateTime.now().toIso8601String().substring(0, 10);
    if (widget.suggestedGrams != null) {
      _quantity.text = widget.suggestedGrams!.toStringAsFixed(3);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _gateway.ingredients();
      final active = items.where((row) => row['isActive'] == true).toList();
      if (mounted) {
        setState(() {
          _ingredients = active;
          _ingredientId = active.any((row) => row['id'] == widget.ingredientId)
              ? widget.ingredientId
              : active.firstOrNull?['id'] as String?;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is ApiException
              ? error.message
              : 'Unable to load ingredients.';
        });
      }
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _received.dispose();
    _expiry.dispose();
    _source.dispose();
    if (widget.gateway == null) (_gateway as InventoryAdminService).close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _ingredientId == null) return;
    final grams = double.tryParse(_quantity.text.trim());
    final cost = double.tryParse(_cost.text.trim());
    if (grams == null ||
        grams <= 0 ||
        cost == null ||
        cost < 0 ||
        _expiry.text.trim().isEmpty) {
      setState(() => _error = 'Enter valid quantity, cost and dates.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _gateway.receiveBatch({
        'ingredientId': _ingredientId,
        'receivedDate': _received.text.trim(),
        'expiryDate': _expiry.text.trim(),
        'quantityGrams': grams,
        'unitCostSnapshot': cost,
        'source': _source.text.trim().isEmpty ? null : _source.text.trim(),
        'receiptKey': _key,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to record the batch. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Restock Ingredient')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Record stock that has physically arrived. A batch and its '
            'inventory movement are saved together. Production remains unconfirmed.',
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_ingredients.isEmpty && !_loading)
            const Text('No active ingredients are available.'),
          if (_ingredients.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _ingredientId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ingredient'),
              items: _ingredients
                  .map(
                    (row) => DropdownMenuItem<String>(
                      value: row['id'] as String,
                      child: Text(
                        row['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _ingredientId = value),
            ),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Received quantity (g)',
            ),
          ),
          TextField(
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Batch cost (MYR/kg)'),
          ),
          TextField(
            controller: _received,
            decoration: const InputDecoration(
              labelText: 'Received date (YYYY-MM-DD)',
            ),
          ),
          TextField(
            controller: _expiry,
            decoration: const InputDecoration(
              labelText: 'Expiry date (YYYY-MM-DD)',
            ),
          ),
          TextField(
            controller: _source,
            decoration: const InputDecoration(
              labelText: 'Supplier/source (optional)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading || _saving || _ingredientId == null
                ? null
                : _save,
            child: Text(_saving ? 'Recording...' : 'Record batch'),
          ),
          if (_saving) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
