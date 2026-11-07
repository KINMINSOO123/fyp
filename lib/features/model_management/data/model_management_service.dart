import '../../../core/network/api_client.dart';
import '../domain/model_review.dart';

abstract interface class ModelManagementGateway {
  Future<List<TrainingCategory>> listCategories();
  Future<ModelReviewPage> listModels({String? breadCategoryId, int page});
  Future<ModelVersionReview> getModel(String id);
  Future<void> train(String breadCategoryId);
  Future<void> evaluate(String modelId);
  Future<void> activate(String modelId, String evaluationId);
  Future<void> restore(String modelId);
}

class ModelManagementService implements ModelManagementGateway {
  ModelManagementService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;

  Map<String, dynamic> _data(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid model-management response.');
    }
    return data;
  }

  @override
  Future<List<TrainingCategory>> listCategories() async {
    final response = await _apiClient.getJson('/api/admin/models/categories');
    final data = response['data'];
    if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid category list.');
    }
    return data
        .map((item) => TrainingCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ModelReviewPage> listModels({
    String? breadCategoryId,
    int page = 1,
  }) async {
    final query = <String, String>{'page': '$page', 'pageSize': '20'};
    if (breadCategoryId != null) query['breadCategoryId'] = breadCategoryId;
    final uri = Uri(path: '/api/admin/models', queryParameters: query);
    return ModelReviewPage.fromJson(
      _data(await _apiClient.getJson(uri.toString())),
    );
  }

  @override
  Future<ModelVersionReview> getModel(String id) async =>
      ModelVersionReview.fromJson(
        _data(
          await _apiClient.getJson(
            '/api/admin/models/${Uri.encodeComponent(id)}',
          ),
        ),
      );

  @override
  Future<void> train(String breadCategoryId) async {
    await _apiClient.postJson('/api/admin/models/train', {
      'breadCategoryId': breadCategoryId,
    }, timeout: const Duration(seconds: 150));
  }

  @override
  Future<void> evaluate(String modelId) async {
    await _apiClient.postJson(
      '/api/admin/models/${Uri.encodeComponent(modelId)}/evaluate',
      {},
      timeout: const Duration(seconds: 150),
    );
  }

  @override
  Future<void> activate(String modelId, String evaluationId) async {
    await _apiClient.postJson(
      '/api/admin/models/${Uri.encodeComponent(modelId)}/activate',
      {'confirm': true, 'evaluationId': evaluationId},
    );
  }

  @override
  Future<void> restore(String modelId) async {
    await _apiClient.postJson(
      '/api/admin/models/${Uri.encodeComponent(modelId)}/restore',
      {'confirm': true},
    );
  }

  void close() => _apiClient.close();
}
