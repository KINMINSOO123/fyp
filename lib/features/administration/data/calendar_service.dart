import '../../../core/network/api_client.dart';

abstract class CalendarGateway {
  Future<Map<String, dynamic>> year(int year);
  Future<Map<String, dynamic>> refresh(int year);
}

class CalendarService implements CalendarGateway {
  CalendarService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;
  Map<String, dynamic> _data(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid KL holiday response.');
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> year(int year) async =>
      _data(await _api.getJson('/api/admin/calendar-events?year=$year'));
  @override
  Future<Map<String, dynamic>> refresh(int year) async => _data(
    await _api.postJson('/api/admin/calendar-events/refresh', {'year': year}),
  );
  void close() => _api.close();
}
