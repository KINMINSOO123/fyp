const notificationTypes = [
  'LOW_STOCK',
  'EXPIRING_BATCH',
  'EXPIRED_BATCH',
  'LOW_CONFIDENCE',
  'LOST_SALES',
  'EXCESSIVE_LEFTOVER',
  'DONATION_STATUS',
  'MODEL_OPERATION_FAILURE',
  'EXTERNAL_SERVICE_FAILURE',
  'SYSTEM_FAILURE',
  'ADMINISTRATIVE_EVENT',
];

class NotificationPreference {
  const NotificationPreference({
    required this.notificationType,
    required this.inAppEnabled,
    required this.pushEnabled,
  });
  final String notificationType;
  final bool inAppEnabled, pushEnabled;
  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    if (!notificationTypes.contains(json['notificationType']) ||
        json['inAppEnabled'] is! bool ||
        json['pushEnabled'] is! bool) {
      throw const FormatException('Invalid notification preference.');
    }
    return NotificationPreference(
      notificationType: json['notificationType'] as String,
      inAppEnabled: json['inAppEnabled'] as bool,
      pushEnabled: json['pushEnabled'] as bool,
    );
  }
}

class BakeryNotification {
  const BakeryNotification({
    required this.id,
    required this.notificationType,
    required this.severity,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });
  final String id, notificationType, severity, title, message, createdAt;
  final bool isRead;
  factory BakeryNotification.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        !notificationTypes.contains(json['notificationType']) ||
        !const ['INFO', 'WARNING', 'CRITICAL'].contains(json['severity']) ||
        json['title'] is! String ||
        json['message'] is! String ||
        json['isRead'] is! bool ||
        json['createdAt'] is! String) {
      throw const FormatException('Invalid notification.');
    }
    return BakeryNotification(
      id: json['id'] as String,
      notificationType: json['notificationType'] as String,
      severity: json['severity'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      isRead: json['isRead'] as bool,
      createdAt: json['createdAt'] as String,
    );
  }
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.page,
    required this.total,
  });
  final List<BakeryNotification> items;
  final int page, total;
  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (json['page'] is! int ||
        json['total'] is! int ||
        items is! List ||
        items.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid notification page.');
    }
    return NotificationPage(
      page: json['page'] as int,
      total: json['total'] as int,
      items: items
          .map(
            (item) => BakeryNotification.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class PendingAction {
  const PendingAction({
    required this.key,
    required this.status,
    required this.date,
    required this.description,
    required this.action,
  });
  final String key, status, date, description;
  final String? action;
  factory PendingAction.fromJson(Map<String, dynamic> json) {
    if (json['key'] is! String ||
        !const ['READY', 'BLOCKED', 'COMPLETE'].contains(json['status']) ||
        json['date'] is! String ||
        json['description'] is! String ||
        (json['action'] != null && json['action'] is! String)) {
      throw const FormatException('Invalid pending action.');
    }
    return PendingAction(
      key: json['key'] as String,
      status: json['status'] as String,
      date: json['date'] as String,
      description: json['description'] as String,
      action: json['action'] as String?,
    );
  }
}

class PendingState {
  const PendingState({required this.date, required this.items});
  final String date;
  final List<PendingAction> items;
  factory PendingState.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (json['date'] is! String ||
        items is! List ||
        items.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid pending state.');
    }
    return PendingState(
      date: json['date'] as String,
      items: items
          .map((item) => PendingAction.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
