import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/api_exception.dart';
import '../data/notification_service.dart';
import '../data/push_registration_manager.dart';
import '../domain/notification_models.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.userId, super.key});
  final String userId;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  RealtimeChannel? _channel;
  NotificationPage? _page;
  bool _loading = true;
  bool _unreadOnly = false;
  int _pageNumber = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime is a recipient-only refresh signal. All reads and mark-read
    // writes still go through the authenticated Node API.
    _channel = Supabase.instance.client
        .channel('notifications:${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: widget.userId,
          ),
          callback: (_) {
            if (mounted) _load();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: widget.userId,
          ),
          callback: (_) {
            if (mounted) _load();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    _service.close();
    super.dispose();
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : error is FormatException
      ? error.message
      : 'Unable to load notifications.';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.list(
        page: _pageNumber,
        unreadOnly: _unreadOnly,
      );
      if (mounted) setState(() => _page = page);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          if (error is ApiException &&
              (error.statusCode == 401 || error.statusCode == 403)) {
            _page = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(BakeryNotification item) async {
    if (item.isRead) return;
    try {
      await _service.markRead(item.id);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _showDeliveries(BakeryNotification item) async {
    try {
      final rows = await _service.deliveries(item.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Push delivery history'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows.isEmpty
                  ? [const Text('No push attempts recorded.')]
                  : rows
                        .map(
                          (row) => Text(
                            'Attempt ${row['attemptNumber']}: '
                            '${row['status']}',
                          ),
                        )
                        .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Preferences',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationPreferencesScreen(),
                ),
              );
              if (mounted) await _load();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: const Text('Unread only'),
                value: _unreadOnly,
                onChanged: (value) async {
                  setState(() {
                    _unreadOnly = value;
                    _pageNumber = 1;
                  });
                  await _load();
                },
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (page != null && page.items.isEmpty && !_loading)
                const Text('No notifications for this view.'),
              for (final item in page?.items ?? <BakeryNotification>[])
                Card(
                  child: ListTile(
                    onTap: () => _showDeliveries(item),
                    leading: Icon(
                      item.isRead
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(item.title),
                    subtitle: Text(
                      '${item.message}\n${item.notificationType} · '
                      '${item.createdAt}',
                    ),
                    isThreeLine: true,
                    trailing: item.isRead
                        ? null
                        : TextButton(
                            onPressed: () => _markRead(item),
                            child: const Text('Mark read'),
                          ),
                  ),
                ),
              if (page != null && page.total > 50)
                Row(
                  children: [
                    TextButton(
                      onPressed: _pageNumber > 1
                          ? () {
                              setState(() => _pageNumber--);
                              _load();
                            }
                          : null,
                      child: const Text('Previous'),
                    ),
                    Expanded(
                      child: Text(
                        'Page $_pageNumber',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: _pageNumber * 50 < page.total
                          ? () {
                              setState(() => _pageNumber++);
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
      ),
    );
  }
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final _service = NotificationService();
  List<NotificationPreference>? _preferences;
  String? _error;
  bool _saving = false;

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
    try {
      final value = await _service.preferences();
      if (mounted) setState(() => _preferences = value);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to load preferences.',
        );
      }
    }
  }

  Future<void> _change(
    NotificationPreference old, {
    bool? inApp,
    bool? push,
  }) async {
    if (_saving) return;
    final updated = NotificationPreference(
      notificationType: old.notificationType,
      inAppEnabled: inApp ?? old.inAppEnabled,
      pushEnabled: push ?? old.pushEnabled,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.savePreference(updated);
      final preferences = _preferences
          ?.map(
            (item) => item.notificationType == updated.notificationType
                ? updated
                : item,
          )
          .toList();
      if (mounted && preferences != null) {
        setState(() => _preferences = preferences);
      }
      if (preferences != null) {
        await PushRegistrationManager.instance.updatePreferences(preferences);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to save preference or register push.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notification Preferences')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'In-app alerts use your account. Push alerts require '
            'Firebase setup and Android notification permission.',
          ),
          if (_saving || _preferences == null) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final pref in _preferences ?? <NotificationPreference>[])
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(pref.notificationType.replaceAll('_', ' ')),
                  ),
                  SwitchListTile(
                    title: const Text('In-app'),
                    value: pref.inAppEnabled,
                    onChanged: _saving
                        ? null
                        : (value) => _change(pref, inApp: value),
                  ),
                  SwitchListTile(
                    title: const Text('Background push'),
                    value: pref.pushEnabled,
                    onChanged: _saving
                        ? null
                        : (value) => _change(pref, push: value),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
