import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../domain/notification_models.dart';
import 'notification_service.dart';

class PushRegistrationManager {
  PushRegistrationManager._();
  static final instance = PushRegistrationManager._();

  StreamSubscription<String>? _refreshSubscription;
  String? _userId;
  String? _registrationId;
  int _generation = 0;
  late final NotificationService _service = NotificationService();

  bool get available => Firebase.apps.isNotEmpty;

  Future<void> start(String userId) async {
    if (!available || _userId == userId) return;
    _userId = userId;
    final generation = ++_generation;
    try {
      final preferences = await _service.preferences();
      if (_generation != generation || _userId != userId) return;
      await updatePreferences(preferences);
    } catch (_) {
      // In-app notifications stay available when Firebase/Node push setup fails.
    }
  }

  Future<void> updatePreferences(
    List<NotificationPreference> preferences,
  ) async {
    if (!available || _userId == null) return;
    final generation = _generation;
    final userId = _userId;
    if (!preferences.any((preference) => preference.pushEnabled)) {
      await _revoke();
      return;
    }
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission();
    if (_generation != generation || _userId != userId) return;
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      await _revoke();
      return;
    }
    final token = await messaging.getToken();
    if (_generation != generation || _userId != userId) return;
    if (token == null || token.isEmpty) return;
    final registered = await _service.registerToken(token);
    if (_generation != generation || _userId != userId) {
      try {
        await _service.deactivateToken(registered);
      } catch (_) {}
      return;
    }
    _registrationId = registered;
    await _refreshSubscription?.cancel();
    _refreshSubscription = messaging.onTokenRefresh.listen((fresh) async {
      if (_generation != generation || _userId != userId) return;
      final oldId = _registrationId;
      try {
        final newId = await _service.registerToken(fresh);
        if (_generation != generation || _userId != userId) {
          await _service.deactivateToken(newId);
          return;
        }
        _registrationId = newId;
        if (oldId != null && oldId != newId) {
          await _service.deactivateToken(oldId);
        }
      } catch (_) {
        // The next explicit app open or preference refresh retries registration.
      }
    });
  }

  Future<void> _revoke() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    final id = _registrationId;
    _registrationId = null;
    if (id != null) {
      try {
        await _service.deactivateToken(id);
      } catch (_) {}
    }
    if (available) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _generation++;
    _userId = null;
    await _revoke();
  }
}
