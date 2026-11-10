import '../../../core/network/api_client.dart';
import '../domain/simulation_result.dart';

abstract interface class PosSimulationGateway {
  Future<String> getBakeryToday();
  Future<SimulationResult> getResult(String date);
  Future<SimulationResult> run(String date);
}

class PosSimulationService implements PosSimulationGateway {
  PosSimulationService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;

  Map<String, dynamic> _data(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid simulation response.');
    }
    return data;
  }

  @override
  Future<String> getBakeryToday() async {
    final data = _data(await _apiClient.getJson('/api/simulations/today'));
    if (data['date'] is! String) {
      throw const FormatException('Invalid bakery date.');
    }
    return data['date'] as String;
  }

  @override
  Future<SimulationResult> getResult(String date) async =>
      SimulationResult.fromJson(
        _data(
          await _apiClient.getJson(
            '/api/simulations/${Uri.encodeComponent(date)}',
          ),
        ),
      );

  @override
  Future<SimulationResult> run(String date) async => SimulationResult.fromJson(
    _data(
      await _apiClient.postJson('/api/simulations', {
        'date': date,
      }, timeout: const Duration(seconds: 45)),
    ),
  );

  void close() => _apiClient.close();
}
