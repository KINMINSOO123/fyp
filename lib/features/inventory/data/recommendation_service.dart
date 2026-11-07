import '../../../core/network/api_client.dart';
import '../domain/recommendation_plan.dart';

abstract interface class RecommendationGateway {
  Future<RecommendationPlan> getPlan(
    String date, {
    String? revisingPredictionId,
  });
  Future<RecommendationPlan> confirm({
    required String predictionId,
    required int finalSelectedQty,
    required String selectedOption,
    required String? decisionReason,
  });
}

class RecommendationService implements RecommendationGateway {
  RecommendationService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;

  RecommendationPlan _parse(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid production planning response.');
    }
    return RecommendationPlan.fromJson(data);
  }

  @override
  Future<RecommendationPlan> getPlan(
    String date, {
    String? revisingPredictionId,
  }) async {
    final path = Uri(
      path: '/api/recommendations/$date',
      queryParameters: revisingPredictionId == null
          ? null
          : {'revisingPredictionId': revisingPredictionId},
    ).toString();
    return _parse(await _apiClient.getJson(path));
  }

  @override
  Future<RecommendationPlan> confirm({
    required String predictionId,
    required int finalSelectedQty,
    required String selectedOption,
    required String? decisionReason,
  }) async {
    return _parse(
      await _apiClient.putJson('/api/production-decisions', {
        'predictionId': predictionId,
        'finalSelectedQty': finalSelectedQty,
        'selectedOption': selectedOption,
        'decisionReason': decisionReason,
      }),
    );
  }

  void close() => _apiClient.close();
}
