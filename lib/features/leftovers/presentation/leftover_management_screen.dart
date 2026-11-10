import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../profile/domain/user_profile.dart';
import '../data/leftover_service.dart';
import '../domain/leftover_models.dart';

class LeftoverManagementScreen extends StatefulWidget {
  const LeftoverManagementScreen({required this.role, this.gateway, super.key});
  final UserRole role;
  final LeftoverGateway? gateway;

  @override
  State<LeftoverManagementScreen> createState() =>
      _LeftoverManagementScreenState();
}

class _LeftoverManagementScreenState extends State<LeftoverManagementScreen> {
  late final LeftoverGateway _gateway;
  LeftoverDay? _day;
  List<DonationRow> _donations = [];
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool get _manager => widget.role == UserRole.bakeryManager;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? LeftoverService();
    _load();
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as LeftoverService).close();
    super.dispose();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to load or save leftovers. Please try again.';
  }

  Future<void> _load([String? date]) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final day = await _gateway.list(date: date ?? _day?.date);
      final donations = _manager
          ? await _gateway.donations(day.date)
          : <DonationRow>[];
      if (!mounted) return;
      setState(() {
        _day = day;
        _donations = donations;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDate() async {
    final date = _day?.date;
    if (date == null || _busy || _loading) return;
    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(date),
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(date).isAfter(DateTime.now())
          ? DateTime.parse(date)
          : DateTime.now(),
    );
    if (chosen != null && mounted) {
      await _load(chosen.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _allocate(LeftoverRow row, {required bool donation}) async {
    if (!_manager || _busy || row.remainingUnallocated == 0) return;
    var submitted = false;
    try {
      final charities = donation
          ? await _gateway.activeCharities()
          : <CharityPartner>[];
      if (!mounted) return;
      if (donation && charities.isEmpty) {
        setState(
          () => _error =
              'No active charity is available. An administrator must add one.',
        );
        return;
      }
      final request = await showDialog<_AllocationRequest>(
        context: context,
        builder: (_) => _AllocationDialog(
          row: row,
          donation: donation,
          charities: charities,
        ),
      );
      if (request == null || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      submitted = true;
      if (donation) {
        await _gateway.donate(
          row.dailyResultId,
          request.quantity,
          request.charityId!,
          request.detail.isEmpty ? null : request.detail,
        );
      } else {
        await _gateway.recordWaste(
          row.dailyResultId,
          request.quantity,
          request.detail,
        );
      }
      if (mounted) await _load(_day?.date);
    } catch (error) {
      if (mounted && submitted) await _load(_day?.date);
      if (mounted) {
        setState(
          () => _error = submitted
              ? '${_message(error)} Review the current balance before submitting again.'
              : _message(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(DonationRow donation) async {
    if (!_manager || _busy) return;
    final next = switch (donation.status) {
      'PENDING' => 'COLLECTED',
      'COLLECTED' => 'COMPLETED',
      _ => null,
    };
    if (next == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update donation status?'),
        content: Text(
          'Mark ${donation.quantity} units for ${donation.charityPartnerName} as $next? This does not allocate them a second time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _gateway.advanceDonation(donation.id, next);
      if (mounted) await _load(_day?.date);
    } catch (error) {
      if (mounted) await _load(_day?.date);
      if (mounted) {
        setState(
          () => _error =
              '${_message(error)} Review the current status before submitting again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    return Scaffold(
      appBar: AppBar(title: const Text('Leftovers and Donations')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(day?.date),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date: ${day?.date ?? 'Loading...'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _chooseDate,
                    child: const Text('Change'),
                  ),
                ],
              ),
              const Text(
                'Simulated sales · unallocated bread is not automatically waste.',
              ),
              if (_loading || _busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (!_loading && day != null && day.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text('No completed simulation results for this date.'),
                ),
              if (day != null)
                for (final row in day.items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.breadCategoryName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Leftover ${row.leftover} · Donated ${row.donated} · Discarded ${row.wasted}',
                          ),
                          Text(
                            'Remaining to allocate: ${row.remainingUnallocated}',
                          ),
                          if (_manager && row.remainingUnallocated > 0)
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _allocate(row, donation: true),
                                  child: const Text('Donate'),
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _allocate(row, donation: false),
                                  child: const Text('Record Waste'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              if (_manager && _donations.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Donation progress',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final donation in _donations)
                  ListTile(
                    title: Text(
                      '${donation.quantity} units · ${donation.charityPartnerName}',
                    ),
                    subtitle: Text(donation.status),
                    trailing:
                        donation.status == 'PENDING' ||
                            donation.status == 'COLLECTED'
                        ? TextButton(
                            onPressed: _busy ? null : () => _advance(donation),
                            child: const Text('Advance'),
                          )
                        : null,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AllocationRequest {
  const _AllocationRequest(this.quantity, this.charityId, this.detail);
  final int quantity;
  final String? charityId;
  final String detail;
}

class _AllocationDialog extends StatefulWidget {
  const _AllocationDialog({
    required this.row,
    required this.donation,
    required this.charities,
  });
  final LeftoverRow row;
  final bool donation;
  final List<CharityPartner> charities;
  @override
  State<_AllocationDialog> createState() => _AllocationDialogState();
}

class _AllocationDialogState extends State<_AllocationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _detail = TextEditingController();
  String? _charityId;
  @override
  void dispose() {
    _quantity.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.donation ? 'Confirm donation' : 'Confirm disposal'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.row.breadCategoryName}: ${widget.row.remainingUnallocated} units available',
            ),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
              validator: (value) {
                final number = int.tryParse(value?.trim() ?? '');
                if (number == null ||
                    number <= 0 ||
                    number > widget.row.remainingUnallocated) {
                  return 'Enter 1 to ${widget.row.remainingUnallocated} units.';
                }
                return null;
              },
            ),
            if (widget.donation)
              DropdownButtonFormField<String>(
                initialValue: _charityId,
                decoration: const InputDecoration(labelText: 'Active charity'),
                items: widget.charities
                    .map(
                      (partner) => DropdownMenuItem(
                        value: partner.id,
                        child: Text(partner.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _charityId = value),
                validator: (value) =>
                    value == null ? 'Choose a charity.' : null,
              ),
            TextFormField(
              controller: _detail,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: widget.donation
                    ? 'Notes (optional)'
                    : 'Disposal reason',
              ),
              validator: widget.donation
                  ? null
                  : (value) => value == null || value.trim().isEmpty
                        ? 'A disposal reason is required.'
                        : null,
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
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _AllocationRequest(
              int.parse(_quantity.text.trim()),
              _charityId,
              _detail.text.trim(),
            ),
          );
        },
        child: Text(widget.donation ? 'Confirm Donation' : 'Confirm Waste'),
      ),
    ],
  );
}
