import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/calendar_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({this.gateway, super.key});
  final CalendarGateway? gateway;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final CalendarGateway _gateway;
  late final TextEditingController _year;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? CalendarService();
    _year = TextEditingController(text: '${DateTime.now().year}');
    _load();
  }

  @override
  void dispose() {
    _year.dispose();
    if (widget.gateway == null) (_gateway as CalendarService).close();
    super.dispose();
  }

  int? get _selectedYear {
    final value = int.tryParse(_year.text.trim());
    return value != null && value >= 2000 && value <= 2100 ? value : null;
  }

  Future<void> _run(bool refresh) async {
    if (_busy) return;
    final year = _selectedYear;
    if (year == null) {
      setState(() => _error = 'Enter a year from 2000 to 2100.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = refresh
          ? await _gateway.refresh(year)
          : await _gateway.year(year);
      if (mounted) setState(() => _summary = data);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to load KL public holidays.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(false);
  Future<void> _refresh() => _run(true);

  @override
  Widget build(BuildContext context) {
    final coverage = _summary?['coverage'];
    final status = _summary?['status']?.toString() ?? 'NOT_SYNCED';
    final events = _summary?['events'];
    final rows = events is List ? events : const [];
    return Scaffold(
      appBar: AppBar(title: const Text('KL Public Holidays')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Published Kuala Lumpur public holidays are cached for '
              'prediction context. The list is read-only. A missing holiday '
              'means an ordinary day only after a successful year sync.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Year',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Load year'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Retry / Refresh'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            Text('Year: ${_summary?['year'] ?? _selectedYear ?? '—'} · Kuala Lumpur (KUL)'),
            Text(
              switch (status) {
                'READY' => 'Sync status: Ready for simulation',
                'REFRESH_DUE' => 'Sync status: Refresh due',
                'INCOMPLETE' => 'Sync status: Incomplete — refresh required',
                _ => 'Sync status: Not synced — refresh required',
              },
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              coverage is Map
                  ? 'Last successful sync: ${coverage['lastSuccessfulAt']}'
                  : 'No successful sync recorded for this year.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (coverage is Map)
              Text('Refresh due: ${coverage['refreshAfter']} · '
                  'published events: ${coverage['eventCount']}'),
            const SizedBox(height: 8),
            Text(
              'KL public holidays (${rows.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final raw in rows)
              if (raw is Map)
                ListTile(
                  title: Text(raw['eventName']?.toString() ?? 'Holiday'),
                  subtitle: Text(
                    '${raw['eventDate']} · '
                    '${raw['sourceReference'] ?? 'Source unavailable'}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
