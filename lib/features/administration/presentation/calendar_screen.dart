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
  final _date = TextEditingController();
  final _name = TextEditingController();
  final _source = TextEditingController();
  String _type = 'PUBLIC_HOLIDAY';
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? CalendarService();
  }

  @override
  void dispose() {
    _date.dispose();
    _name.dispose();
    _source.dispose();
    if (widget.gateway == null) (_gateway as CalendarService).close();
    super.dispose();
  }

  String _message(Object error) => error is ApiException
      ? error.message : 'Unable to load or save calendar events.';

  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final events = await _gateway.events(_date.text.trim());
      if (mounted) setState(() => _events = events);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _gateway.add({
        'eventDate': _date.text.trim(), 'eventType': _type,
        'eventName': _name.text.trim(),
        'sourceReference': _source.text.trim(),
      });
      final events = await _gateway.events(_date.text.trim());
      if (!mounted) return;
      setState(() { _events = events; _name.clear(); _source.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Calendar event recorded.')));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calendar Events')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16),
      children: [
        const Text('Enter events from a checked source before generating '
          'predictions for that date. An empty list does not verify that '
          'the date has no holiday.'),
        const SizedBox(height: 12),
        TextField(controller: _date, decoration: const InputDecoration(
          labelText: 'Date (YYYY-MM-DD)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _busy ? null : _load,
          child: const Text('Load date events')),
        const Divider(height: 32),
        DropdownButtonFormField<String>(initialValue: _type,
          decoration: const InputDecoration(labelText: 'Event type',
            border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'PUBLIC_HOLIDAY',
              child: Text('Public holiday')),
            DropdownMenuItem(value: 'SCHOOL_HOLIDAY',
              child: Text('School holiday')),
            DropdownMenuItem(value: 'LOCAL_EVENT', child: Text('Local event')),
            DropdownMenuItem(value: 'RELIGIOUS_HOLIDAY',
              child: Text('Religious holiday')),
          ], onChanged: _busy ? null : (value) {
            if (value != null) setState(() => _type = value);
          }),
        const SizedBox(height: 8),
        TextField(controller: _name, decoration: const InputDecoration(
          labelText: 'Event name', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _source, decoration: const InputDecoration(
          labelText: 'Source reference', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _add,
          child: const Text('Record event')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: TextStyle(
          color: Theme.of(context).colorScheme.error)),
        const Divider(height: 32),
        Text('Stored events (${_events.length})',
          style: Theme.of(context).textTheme.titleMedium),
        for (final event in _events) ListTile(
          title: Text(event['eventName']?.toString() ?? 'Event'),
          subtitle: Text('${event['eventType']} · '
            '${event['sourceReference'] ?? 'Source not recorded'}'),
        ),
      ])),
  );
}
