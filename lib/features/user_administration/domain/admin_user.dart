import '../../profile/domain/user_profile.dart';

class AdminUser {
  const AdminUser({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.accountStatus,
    required this.createdAt,
    required this.profileStatus,
  });

  final String userId;
  final String? email;
  final String? fullName;
  final UserRole? role;
  final AccountStatus? accountStatus;
  final DateTime createdAt;
  final String profileStatus;

  bool get hasCompleteProfile => profileStatus == 'COMPLETE';

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'];
    final email = json['email'];
    final fullName = json['fullName'];
    final roleText = json['role'];
    final statusText = json['accountStatus'];
    final createdAtText = json['createdAt'];
    final profileStatus = json['profileStatus'];

    if (userId is! String ||
        createdAtText is! String ||
        profileStatus is! String ||
        (email != null && email is! String) ||
        (fullName != null && fullName is! String)) {
      throw const FormatException('Invalid administrator user response.');
    }

    final createdAt = DateTime.tryParse(createdAtText);

    if (createdAt == null) {
      throw const FormatException('Invalid account creation date.');
    }

    final role = switch (roleText) {
      'BAKERY_MANAGER' => UserRole.bakeryManager,
      'SYSTEM_ADMINISTRATOR' => UserRole.systemAdministrator,
      null => null,
      _ => throw const FormatException('Invalid administrator user role.'),
    };

    final accountStatus = switch (statusText) {
      'ACTIVE' => AccountStatus.active,
      'INACTIVE' => AccountStatus.inactive,
      null => null,
      _ => throw const FormatException('Invalid administrator account status.'),
    };

    if (profileStatus != 'COMPLETE' && profileStatus != 'MISSING') {
      throw const FormatException('Invalid profile status.');
    }

    return AdminUser(
      userId: userId,
      email: email as String?,
      fullName: fullName as String?,
      role: role,
      accountStatus: accountStatus,
      createdAt: createdAt,
      profileStatus: profileStatus,
    );
  }
}

class AdminUserPage {
  const AdminUserPage({
    required this.users,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<AdminUser> users;
  final int page;
  final int pageSize;
  final int total;
}
