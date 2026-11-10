import '../../../core/network/api_client.dart';

abstract class CalendarGateway {
  Future<List<Map<String, dynamic>>> events(String date);
  Future<Map<String, dynamic>> add(Map<String, dynamic> values);
}

class CalendarService implements CalendarGateway {
  CalendarService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  @override
  Future<List<Map<String, dynamic>>> events(String date) async {
    final uri = Uri(path: '/api/admin/calendar-events',
      queryParameters: {'date': date});
    final response = await _api.getJson(uri.toString());
    final data = response['data'];
    if (data is! List) throw const FormatException('Invalid calendar data.');
    return data.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid calendar entry.');
      }
      return item;
    }).toList();
  }

  @override
  Future<Map<String, dynamic>> add(Map<String, dynamic> values) async {
    final response = await _api.postJson('/api/admin/calendar-events', values);
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved calendar entry.');
    }
    return data;
  }

  void close() => _api.close();
}
