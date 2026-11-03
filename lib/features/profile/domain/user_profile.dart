enum UserRole { bakeryManager, systemAdministrator }

enum AccountStatus { active, inactive }

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.accountStatus,
  });

  final String userId;
  final String fullName;
  final UserRole role;
  final AccountStatus accountStatus;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'];
    final fullName = json['fullName'];
    final roleText = json['role'];
    final statusText = json['accountStatus'];

    if (userId is! String ||
        fullName is! String ||
        roleText is! String ||
        statusText is! String) {
      throw const FormatException('Invalid user profile response.');
    }

    final role = switch (roleText) {
      'BAKERY_MANAGER' => UserRole.bakeryManager,
      'SYSTEM_ADMINISTRATOR' => UserRole.systemAdministrator,
      _ => throw const FormatException('Invalid user role.'),
    };

    final accountStatus = switch (statusText) {
      'ACTIVE' => AccountStatus.active,
      'INACTIVE' => AccountStatus.inactive,
      _ => throw const FormatException('Invalid account status.'),
    };

    return UserProfile(
      userId: userId,
      fullName: fullName,
      role: role,
      accountStatus: accountStatus,
    );
  }
}
