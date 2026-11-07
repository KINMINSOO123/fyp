import '../../../core/network/api_client.dart';
import '../domain/daily_prediction.dart';

abstract interface class PredictionGateway {
  Future<NextPredictionState> getNextDayState();
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
  Future<void> generateNextDay() async {
    await _apiClient.postJson('/api/predictions', <String, dynamic>{});
  }

  void close() => _apiClient.close();
}
