import '../../../core/network/api_client.dart';

class AiRecipeIngredient {
  const AiRecipeIngredient({
    required this.name,
    required this.gramsPerBread,
    required this.availability,
    required this.availableGrams,
  });
  final String name;
  final num gramsPerBread;
  final String availability;
  final num availableGrams;

  factory AiRecipeIngredient.fromJson(Map<String, dynamic> json) =>
      AiRecipeIngredient(
        name: json['ingredientName'] as String,
        gramsPerBread: json['gramsPerBread'] as num,
        availability: json['availability'] as String,
        availableGrams: json['availableGrams'] as num,
      );
}

class AiBreadSuggestion {
  const AiBreadSuggestion({
    required this.name,
    required this.description,
    required this.reason,
    required this.recipe,
  });
  final String name;
  final String description;
  final String reason;
  final List<AiRecipeIngredient> recipe;

  factory AiBreadSuggestion.fromJson(Map<String, dynamic> json) =>
      AiBreadSuggestion(
        name: json['name'] as String,
        description: json['description'] as String,
        reason: json['reason'] as String,
        recipe: (json['recipe'] as List<dynamic>)
            .map(
              (item) =>
                  AiRecipeIngredient.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

abstract class AiSuggestionsGateway {
  Future<List<AiBreadSuggestion>> generate(String description);
}

class AiSuggestionsService implements AiSuggestionsGateway {
  AiSuggestionsService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;

  @override
  Future<List<AiBreadSuggestion>> generate(String description) async {
    final response = await _apiClient.postJson('/api/admin/ai-suggestions', {
      'description': description,
    }, timeout: const Duration(seconds: 30));
    final data = response['data'] as Map<String, dynamic>;
    return (data['suggestions'] as List<dynamic>)
        .map((item) => AiBreadSuggestion.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  void close() => _apiClient.close();
}

abstract class AiReviewGateway {
  Future<Map<String, dynamic>> catalogue();
  Future<void> create(Map<String, dynamic> payload);
}

class AiReviewService implements AiReviewGateway {
  AiReviewService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  @override
  Future<Map<String, dynamic>> catalogue() async {
    final response = await _api.getJson(
      '/api/admin/ai-suggestions/review-context',
    );
    return response['data'] as Map<String, dynamic>;
  }

  @override
  Future<void> create(Map<String, dynamic> payload) async {
    await _api.postJson('/api/admin/ai-suggestions/reviewed', payload);
  }

  void close() => _api.close();
}
