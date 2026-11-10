import 'package:flutter/material.dart';

import '../data/notification_service.dart';
import '../domain/notification_models.dart';

class PendingActionsPanel extends StatefulWidget {
  const PendingActionsPanel({super.key});
  @override
  State<PendingActionsPanel> createState() => _PendingActionsPanelState();
}

class _PendingActionsPanelState extends State<PendingActionsPanel> {
  final _service = NotificationService();
  PendingState? _state;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await _service.pending();
      if (mounted) setState(() => _state = state);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Pending actions are unavailable. Refresh to try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Current workflow',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh pending actions',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const Text('Indicators update when you open or refresh the app.'),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_state != null && _state!.items.isEmpty)
            const Text('Administration links are available below.'),
          for (final item in _state?.items ?? <PendingAction>[])
            ListTile(
              dense: true,
              leading: Icon(
                item.status == 'COMPLETE'
                    ? Icons.check_circle_outline
                    : item.status == 'READY'
                    ? Icons.pending_actions
                    : Icons.lock_outline,
              ),
              title: Text(item.key.replaceAll('_', ' ')),
              subtitle: Text('${item.status} · ${item.description}'),
            ),
        ],
      ),
    ),
  );
}
