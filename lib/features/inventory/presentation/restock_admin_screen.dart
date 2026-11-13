import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/inventory_admin_service.dart';
import '../data/restock_service.dart';
import '../../profile/domain/user_profile.dart';
import 'dialog_controller_scope.dart';

String _receiptKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class RestockAdminScreen extends StatefulWidget {
  const RestockAdminScreen({
    this.restockGateway,
    this.inventoryGateway,
    this.role = UserRole.systemAdministrator,
    super.key,
  });
  final RestockGateway? restockGateway;
  final InventoryAdminGateway? inventoryGateway;
  final UserRole role;
  @override
  State<RestockAdminScreen> createState() => _RestockAdminScreenState();
}

class _RestockAdminScreenState extends State<RestockAdminScreen> {
  bool get _manager => widget.role == UserRole.bakeryManager;
  late final RestockGateway _restock;
  late final InventoryAdminGateway _inventory;
  List<Map<String, dynamic>> _requests = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restock = widget.restockGateway ?? RestockService();
    _inventory = widget.inventoryGateway ?? InventoryAdminService();
    _load();
  }

  @override
  void dispose() {
    if (widget.restockGateway == null) (_restock as RestockService).close();
    if (widget.inventoryGateway == null) {
      (_inventory as InventoryAdminService).close();
    }
    super.dispose();
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : 'Unable to update the restock request.';
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await _restock.list(administrator: !_manager);
      requests.sort((a, b) {
        bool active(Map<String, dynamic> row) =>
            row['status'] == 'PENDING' || row['status'] == 'PARTIALLY_RECEIVED';
        return (active(b) ? 1 : 0) - (active(a) ? 1 : 0);
      });
      if (mounted) setState(() => _requests = requests);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _receive(Map<String, dynamic> item) async {
    final key = _receiptKey();
    final received = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final expiry = TextEditingController();
    final quantity = TextEditingController(
      text: (item['outstandingGrams'] as num).toStringAsFixed(3),
    );
    final cost = TextEditingController();
    final source = TextEditingController();
    String? error;
    bool busy = false;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => DialogControllerScope(
        controllers: [received, expiry, quantity, cost, source],
        child: StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: Text('Receive ${item['ingredientName']}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Outstanding: ${item['outstandingGrams']} g'),
                  TextField(
                    controller: received,
                    decoration: const InputDecoration(
                      labelText: 'Receipt date (YYYY-MM-DD)',
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
                      labelText: 'Received grams',
                    ),
                  ),
                  TextField(
                    controller: cost,
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
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final grams = double.tryParse(quantity.text.trim());
                        final unitCost = double.tryParse(cost.text.trim());
                        if (grams == null ||
                            grams <= 0 ||
                            unitCost == null ||
                            unitCost < 0 ||
                            expiry.text.trim().isEmpty) {
                          refresh(() => error = 'Enter valid receipt values.');
                          return;
                        }
                        refresh(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await _inventory.receiveBatch({
                            'ingredientId': item['ingredientId'],
                            'receivedDate': received.text.trim(),
                            'expiryDate': expiry.text.trim(),
                            'quantityGrams': grams,
                            'unitCostSnapshot': unitCost,
                            'source': source.text.trim().isEmpty
                                ? null
                                : source.text.trim(),
                            'restockRequestItemId': item['id'],
                            'receiptKey': key,
                          });
                          refresh(() => busy = false);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (failure) {
                          refresh(() {
                            error = _message(failure);
                            busy = false;
                          });
                        }
                      },
                child: const Text('Record Batch'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _cancel(Map<String, dynamic> request) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel outstanding quantities'),
        content: TextField(
          controller: reason,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Audit reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Outstanding'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || text.isEmpty || !mounted) return;
    try {
      await _restock.cancel(request['id'] as String, text);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Restock Requests'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh requests',
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _manager
                ? 'Record physical stock as an inventory batch. A request alone never adds stock.'
                : 'View manager restock requests and receipts. Batch changes are manager-only.',
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final request in _requests)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Production ${request['productionDate']} · ${request['status']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Requested by ${request['requesterUserId']}'),
                    for (final raw in (request['items'] as List))
                      Builder(
                        builder: (context) {
                          final item = raw as Map<String, dynamic>;
                          final open =
                              (item['outstandingGrams'] as num) > 0 &&
                              (request['status'] == 'PENDING' ||
                                  request['status'] == 'PARTIALLY_RECEIVED');
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['ingredientName']}: requested '
                                '${item['requestedGrams']} g, received '
                                '${item['receivedGrams']} g, cancelled '
                                '${item['cancelledGrams']} g, outstanding '
                                '${item['outstandingGrams']} g',
                              ),
                              if (open && _manager)
                                TextButton(
                                  onPressed: () => _receive(item),
                                  child: const Text('Receive Batch'),
                                ),
                            ],
                          );
                        },
                      ),
                    if (_manager &&
                        (request['status'] == 'PENDING' ||
                            request['status'] == 'PARTIALLY_RECEIVED'))
                      OutlinedButton(
                        onPressed: () => _cancel(request),
                        child: const Text('Cancel Outstanding'),
                      ),
                    if (request['cancellationReason'] != null)
                      Text('Cancellation: ${request['cancellationReason']}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
