import '../../../core/network/api_client.dart';
import '../domain/notification_models.dart';

class NotificationService {
  NotificationService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;

  Map<String, dynamic> _map(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification response.');
    }
    return data;
  }

  Future<NotificationPage> list({
    int page = 1,
    bool unreadOnly = false,
  }) async => NotificationPage.fromJson(
    _map(
      await _apiClient.getJson(
        '/api/notifications?page=$page&unreadOnly=$unreadOnly',
      ),
    ),
  );

  Future<List<NotificationPreference>> preferences() async {
    final response = await _apiClient.getJson('/api/notification-preferences');
    final data = response['data'];
    if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid notification preferences.');
    }
    return data
        .map(
          (item) =>
              NotificationPreference.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> savePreference(NotificationPreference preference) async {
    await _apiClient.patchJson('/api/notification-preferences', {
      'notificationType': preference.notificationType,
      'inAppEnabled': preference.inAppEnabled,
      'pushEnabled': preference.pushEnabled,
    });
  }

  Future<void> markRead(String notificationId) async {
    await _apiClient.patchJson(
      '/api/notifications/${Uri.encodeComponent(notificationId)}/read',
      {},
    );
  }

  Future<List<Map<String, dynamic>>> deliveries(String notificationId) async {
    final response = await _apiClient.getJson(
      '/api/notifications/${Uri.encodeComponent(notificationId)}/deliveries',
    );
    final data = response['data'];
    if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid delivery history.');
    }
    return data.cast<Map<String, dynamic>>();
  }

  Future<String> registerToken(String token) async {
    final data = _map(
      await _apiClient.postJson('/api/fcm-tokens', {
        'token': token,
        'deviceInfo': 'Android',
      }),
    );
    if (data['id'] is! String) {
      throw const FormatException('Invalid device registration.');
    }
    return data['id'] as String;
  }

  Future<void> deactivateToken(String id) async {
    await _apiClient.deleteJson('/api/fcm-tokens/${Uri.encodeComponent(id)}');
  }

  Future<PendingState> pending() async => PendingState.fromJson(
    _map(await _apiClient.getJson('/api/pending-actions')),
  );

  void close() => _apiClient.close();
}
