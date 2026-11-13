import '../../../core/network/api_client.dart';

class RestockPreview {
  const RestockPreview({
    required this.targetDate,
    required this.desiredQuantities,
    required this.shortages,
  });
  final String targetDate;
  final List<Map<String, dynamic>> desiredQuantities;
  final List<Map<String, dynamic>> shortages;
  bool get needsRestock => shortages.isNotEmpty;

  factory RestockPreview.fromJson(Map<String, dynamic> data) {
    final desired = data['desiredQuantities'];
    final shortages = data['shortages'];
    if (data['targetDate'] is! String ||
        desired is! List ||
        shortages is! List ||
        desired.any((row) => row is! Map) ||
        shortages.any((row) => row is! Map)) {
      throw const FormatException('Invalid restock preview.');
    }
    return RestockPreview(
      targetDate: data['targetDate'] as String,
      desiredQuantities: desired.cast<Map<String, dynamic>>(),
      shortages: shortages.cast<Map<String, dynamic>>(),
    );
  }
  Map<String, dynamic> get expectedPlan => {
    'desiredQuantities': desiredQuantities
        .map(
          (row) => {
            'breadCategoryId': row['breadCategoryId'],
            'desiredQty': row['desiredQty'],
          },
        )
        .toList(),
    'shortages': shortages
        .map(
          (row) => {
            'ingredientId': row['ingredientId'],
            'additionalGrams': row['additionalGrams'],
          },
        )
        .toList(),
  };
}

abstract interface class RestockGateway {
  Future<RestockPreview> preview(String date);
  Future<Map<String, dynamic>> submit(RestockPreview preview);
  Future<List<Map<String, dynamic>>> list({required bool administrator});
  Future<void> cancel(String requestId, String reason);
}

class RestockService implements RestockGateway {
  RestockService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;
  Map<String, dynamic> _object(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid restock response.');
    }
    return data;
  }

  @override
  Future<RestockPreview> preview(String date) async => RestockPreview.fromJson(
    _object(await _api.getJson('/api/restock-requests/preview/$date')),
  );
  @override
  Future<Map<String, dynamic>> submit(RestockPreview preview) async => _object(
    await _api.postJson('/api/restock-requests', {
      'targetDate': preview.targetDate,
      'expectedPlan': preview.expectedPlan,
      'confirmed': true,
    }),
  );
  @override
  Future<List<Map<String, dynamic>>> list({required bool administrator}) async {
    final path = administrator
        ? '/api/admin/restock-requests'
        : '/api/restock-requests';
    final data = (await _api.getJson(path))['data'];
    if (data is! List || data.any((row) => row is! Map<String, dynamic>)) {
      throw const FormatException('Invalid restock requests.');
    }
    return data.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> cancel(String requestId, String reason) async {
    await _api.postJson('/api/restock-requests/$requestId/cancel', {
      'reason': reason,
    });
  }

  void close() => _api.close();
}
