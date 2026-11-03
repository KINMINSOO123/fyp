import '../../../core/network/api_client.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/admin_user.dart';

class UserAdministrationService {
  UserAdministrationService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<AdminUserPage> listUsers({int page = 1, int pageSize = 20}) async {
    final response = await _apiClient.getJson(
      '/api/admin/users?page=$page&pageSize=$pageSize',
    );

    final data = response['data'];
    final pagination = response['pagination'];

    if (data is! List || pagination is! Map<String, dynamic>) {
      throw const FormatException('Invalid user-list response.');
    }

    final users = data.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid user-list item.');
      }

      return AdminUser.fromJson(item);
    }).toList();

    final returnedPage = pagination['page'];
    final returnedPageSize = pagination['pageSize'];
    final total = pagination['total'];

    if (returnedPage is! int || returnedPageSize is! int || total is! int) {
      throw const FormatException('Invalid user-list pagination.');
    }

    return AdminUserPage(
      users: users,
      page: returnedPage,
      pageSize: returnedPageSize,
      total: total,
    );
  }

  Future<AdminUser> createUser({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    AccountStatus accountStatus = AccountStatus.active,
  }) async {
    final response = await _apiClient.postJson('/api/admin/users', {
      'email': email,
      'password': password,
      'fullName': fullName,
      'role': _roleValue(role),
      'accountStatus': _accountStatusValue(accountStatus),
    });

    final data = response['data'];

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid created-user response.');
    }

    return AdminUser.fromJson(data);
  }

  Future<UserProfile> updateUser({
    required String userId,
    String? fullName,
    UserRole? role,
    AccountStatus? accountStatus,
  }) async {
    final body = <String, dynamic>{};

    if (fullName != null) {
      body['fullName'] = fullName;
    }

    if (role != null) {
      body['role'] = _roleValue(role);
    }

    if (accountStatus != null) {
      body['accountStatus'] = _accountStatusValue(accountStatus);
    }

    final response = await _apiClient.patchJson(
      '/api/admin/users/$userId',
      body,
    );

    final data = response['data'];

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid updated-user response.');
    }

    return UserProfile.fromJson(data);
  }

  String _roleValue(UserRole role) {
    return switch (role) {
      UserRole.bakeryManager => 'BAKERY_MANAGER',
      UserRole.systemAdministrator => 'SYSTEM_ADMINISTRATOR',
    };
  }

  String _accountStatusValue(AccountStatus status) {
    return switch (status) {
      AccountStatus.active => 'ACTIVE',
      AccountStatus.inactive => 'INACTIVE',
    };
  }

  void close() {
    _apiClient.close();
  }
}
