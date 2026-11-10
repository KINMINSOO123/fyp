import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/administration_service.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({this.gateway, super.key});
  final AdministrationGateway? gateway;
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late final AdministrationGateway _gateway;
  final _eventType = TextEditingController();
  final _actor = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  String? _outcome;
  List<Map<String, dynamic>> _events = const [];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? AdministrationService();
    _load();
  }

  @override
  void dispose() {
    _eventType.dispose();
    _actor.dispose();
    if (widget.gateway == null) (_gateway as AdministrationService).close();
    super.dispose();
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final filters = <String, String>{'page': '$_page'};
      if (_from != null) filters['from'] = _date(_from!);
      if (_to != null) filters['to'] = _date(_to!);
      if (_eventType.text.trim().isNotEmpty) {
        filters['eventType'] = _eventType.text.trim().toUpperCase();
      }
      if (_actor.text.trim().isNotEmpty) {
        filters['actorUserId'] = _actor.text.trim();
      }
      if (_outcome != null) filters['outcome'] = _outcome!;
      final data = await _gateway.audit(filters);
      final items = data['items'];
      final total = data['total'];
      if (items is! List || total is! int) {
        throw const FormatException('Invalid audit response.');
      }
      final events = items.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid audit item.');
        }
        return item;
      }).toList();
      if (!mounted) return;
      setState(() {
        _events = events;
        _total = total;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to load audit events.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: from ? (_from ?? DateTime.now()) : (_to ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (from) {
        _from = selected;
      } else {
        _to = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audit History')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Read-only administrative and operational event history. Date filters use UTC.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _pickDate(true),
                child: Text(
                  _from == null ? 'From date' : 'From ${_date(_from!)}',
                ),
              ),
              OutlinedButton(
                onPressed: () => _pickDate(false),
                child: Text(_to == null ? 'To date' : 'To ${_date(_to!)}'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
                child: const Text('Clear dates'),
              ),
            ],
          ),
          TextField(
            controller: _eventType,
            decoration: const InputDecoration(
              labelText: 'Event type (optional)',
            ),
          ),
          TextField(
            controller: _actor,
            decoration: const InputDecoration(
              labelText: 'Actor user ID (optional)',
            ),
          ),
          DropdownButtonFormField<String?>(
            initialValue: _outcome,
            decoration: const InputDecoration(labelText: 'Outcome'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Any')),
              DropdownMenuItem<String?>(
                value: 'SUCCESS',
                child: Text('Success'),
              ),
              DropdownMenuItem<String?>(
                value: 'FAILURE',
                child: Text('Failure'),
              ),
            ],
            onChanged: (value) => setState(() => _outcome = value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading
                ? null
                : () {
                    _page = 1;
                    _load();
                  },
            child: const Text('Apply filters'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!_loading && _events.isEmpty)
            const Text('No audit events for these filters.'),
          for (final event in _events)
            Card(
              child: ListTile(
                title: Text(event['eventType']?.toString() ?? 'Event'),
                subtitle: Text(
                  '${event['createdAt'] ?? ''}\n'
                  '${event['outcome'] ?? ''} · ${event['severity'] ?? ''}\n'
                  'Actor: ${event['actorUserId'] ?? 'System'}\n'
                  'Entity: ${event['entityType'] ?? '—'} '
                  '${event['entityId'] ?? ''}',
                ),
                isThreeLine: true,
              ),
            ),
          if (_total > 50)
            Row(
              children: [
                TextButton(
                  onPressed: _page > 1 && !_loading
                      ? () {
                          setState(() => _page--);
                          _load();
                        }
                      : null,
                  child: const Text('Previous'),
                ),
                Expanded(
                  child: Text('Page $_page', textAlign: TextAlign.center),
                ),
                TextButton(
                  onPressed: _page * 50 < _total && !_loading
                      ? () {
                          setState(() => _page++);
                          _load();
                        }
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
