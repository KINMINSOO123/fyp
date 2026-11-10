import '../../../core/network/api_client.dart';

abstract class AdministrationGateway {
  Future<Map<String, dynamic>> settings();
  Future<Map<String, dynamic>> serviceStatus();
  Future<List<Map<String, dynamic>>> activeCategories();
  Future<Map<String, dynamic>> saveBakery(Map<String, dynamic> values);
  Future<Map<String, dynamic>> saveSetting(String key, Object value);
  Future<Map<String, dynamic>> audit(Map<String, String> filters);
}

class AdministrationService implements AdministrationGateway {
  AdministrationService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  Map<String, dynamic> _data(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid administration response.');
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> settings() async =>
      _data(await _api.getJson('/api/admin/settings'));

  @override
  Future<Map<String, dynamic>> serviceStatus() async =>
      _data(await _api.getJson('/api/admin/service-status'));

  @override
  Future<List<Map<String, dynamic>>> activeCategories() async {
    final response = await _api.getJson('/api/admin/inventory/categories');
    final items = response['data'];
    if (items is! List) {
      throw const FormatException('Invalid category list.');
    }
    return items
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid category.');
          }
          return item;
        })
        .where((item) => item['isActive'] == true)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> saveBakery(Map<String, dynamic> values) async =>
      _data(await _api.patchJson('/api/admin/settings/bakery', values));

  @override
  Future<Map<String, dynamic>> saveSetting(String key, Object value) async =>
      _data(await _api.patchJson('/api/admin/settings/$key', {'value': value}));

  @override
  Future<Map<String, dynamic>> audit(Map<String, String> filters) async {
    final uri = Uri(path: '/api/admin/audit', queryParameters: filters);
    return _data(await _api.getJson(uri.toString()));
  }

  void close() => _api.close();
}
