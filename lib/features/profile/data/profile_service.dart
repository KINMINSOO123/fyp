import '../../../core/network/api_client.dart';
import '../domain/user_profile.dart';

class ProfileService {
  ProfileService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<UserProfile> getOwnProfile() async {
    final response = await _apiClient.getJson('/api/profile/me');

    final data = response['data'];

    if (data is! Map<String, dynamic>) {
      throw const FormatException('The server returned an invalid profile.');
    }

    return UserProfile.fromJson(data);
  }

  Future<UserProfile> updateFullName(String fullName) async {
    final response = await _apiClient.patchJson('/api/profile/me', {
      'fullName': fullName,
    });

    final data = response['data'];

    if (data is! Map<String, dynamic>) {
      throw const FormatException('The server returned an invalid profile.');
    }

    return UserProfile.fromJson(data);
  }

  void close() {
    _apiClient.close();
  }
}
