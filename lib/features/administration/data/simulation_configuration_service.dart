import '../../../core/network/api_client.dart';

abstract class SimulationConfigurationGateway {
  Future<Map<String, dynamic>> load();
  Future<void> saveManual(String categoryId, double value);
  Future<void> saveImported(String categoryId);
  Future<void> saveScenario(Map<String, dynamic> value);
}

class SimulationConfigurationService implements SimulationConfigurationGateway {
  SimulationConfigurationService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();
  final ApiClient _api;
  @override
  Future<Map<String, dynamic>> load() async {
    final response = await _api.getJson('/api/admin/simulation');
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid simulation settings.');
    }
    return data;
  }

  @override
  Future<void> saveManual(String categoryId, double value) async {
    await _api.putJson('/api/admin/simulation/baselines/$categoryId', {
      'source': 'MANUAL',
      'baseDemand': value,
    });
  }

  @override
  Future<void> saveImported(String categoryId) async {
    await _api.putJson('/api/admin/simulation/baselines/$categoryId', {
      'source': 'IMPORTED_HISTORICAL_AVERAGE',
    });
  }

  @override
  Future<void> saveScenario(Map<String, dynamic> value) async {
    await _api.patchJson('/api/admin/simulation/scenario', value);
  }

  void close() => _api.close();
}
