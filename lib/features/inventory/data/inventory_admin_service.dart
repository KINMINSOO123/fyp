import '../../../core/network/api_client.dart';

abstract interface class InventoryAdminGateway {
  Future<List<Map<String, dynamic>>> categories();
  Future<List<Map<String, dynamic>>> ingredients();
  Future<List<Map<String, dynamic>>> recipe(String categoryId);
  Future<List<Map<String, dynamic>>> batches(int page);
  Future<void> saveCategory(Map<String, dynamic> data, {String? id});
  Future<void> saveIngredient(Map<String, dynamic> data, {String? id});
  Future<void> replaceRecipe(
    String categoryId,
    List<Map<String, dynamic>> items,
  );
  Future<void> receiveBatch(Map<String, dynamic> data);
  Future<void> removeBatchStock(String batchId, Map<String, dynamic> data);
  Future<int> scanAlerts();
}

class InventoryAdminService implements InventoryAdminGateway {
  InventoryAdminService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    final data = response['data'];
    final list = data is List
        ? data
        : data is Map
        ? data['items']
        : null;
    if (list is! List) {
      throw const FormatException('Invalid inventory response.');
    }
    return list.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid inventory item.');
      }
      return item;
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> categories() async =>
      _items(await _api.getJson('/api/admin/inventory/categories'));
  @override
  Future<List<Map<String, dynamic>>> ingredients() async =>
      _items(await _api.getJson('/api/admin/inventory/ingredients'));
  @override
  Future<List<Map<String, dynamic>>> recipe(String categoryId) async => _items(
    await _api.getJson('/api/admin/inventory/categories/$categoryId/recipe'),
  );
  @override
  Future<List<Map<String, dynamic>>> batches(int page) async =>
      _items(await _api.getJson('/api/admin/inventory/batches?page=$page'));
  @override
  Future<void> saveCategory(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await _api.postJson('/api/admin/inventory/categories', data);
    } else {
      await _api.patchJson('/api/admin/inventory/categories/$id', data);
    }
  }

  @override
  Future<void> saveIngredient(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await _api.postJson('/api/admin/inventory/ingredients', data);
    } else {
      await _api.patchJson('/api/admin/inventory/ingredients/$id', data);
    }
  }

  @override
  Future<void> replaceRecipe(
    String categoryId,
    List<Map<String, dynamic>> items,
  ) async {
    await _api.putJson('/api/admin/inventory/categories/$categoryId/recipe', {
      'items': items,
    });
  }

  @override
  Future<void> receiveBatch(Map<String, dynamic> data) async {
    await _api.postJson('/api/admin/inventory/batches', data);
  }

  @override
  Future<void> removeBatchStock(
    String batchId,
    Map<String, dynamic> data,
  ) async {
    await _api.patchJson('/api/admin/inventory/batches/$batchId/stock', data);
  }

  @override
  Future<int> scanAlerts() async {
    final response = await _api.postJson(
      '/api/admin/inventory/scan-alerts',
      {},
    );
    final data = response['data'];
    if (data is! Map<String, dynamic> || data['detected'] is! int) {
      throw const FormatException('Invalid inventory alert result.');
    }
    return data['detected'] as int;
  }

  void close() => _api.close();
}
