import '../../../core/network/api_client.dart';
import '../domain/daily_prediction.dart';

abstract interface class PredictionGateway {
  Future<NextPredictionState> getNextDayState();
  Future<List<DailyPrediction>> getByDate(String date);
  Future<void> generateNextDay();
}

class PredictionService implements PredictionGateway {
  PredictionService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  @override
  Future<NextPredictionState> getNextDayState() async {
    final response = await _apiClient.getJson('/api/predictions/next');
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid next-day prediction response.');
    }
    return NextPredictionState.fromJson(data);
  }

  @override
  Future<List<DailyPrediction>> getByDate(String date) async {
    final data = (await _apiClient.getJson('/api/predictions/$date'))['data'];
    if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid saved prediction response.');
    }
    return data
        .map((item) => DailyPrediction.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> generateNextDay() async {
    await _apiClient.postJson('/api/predictions', <String, dynamic>{});
  }

  void close() => _apiClient.close();
}
