import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../domain/report_models.dart';

abstract interface class ReportGateway {
  Future<BakeryReport> get(Map<String, String> filters);
  Future<List<ReportCategory>> categories();
  Future<String> export(Map<String, String> filters, String format);
}

class ReportService implements ReportGateway {
  ReportService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;
  static const _channel = MethodChannel('smart_bakery/report_exports');

  String _path(String path, Map<String, String> filters) => Uri(
    path: path,
    queryParameters: filters.isEmpty ? null : filters,
  ).toString();

  @override
  Future<BakeryReport> get(Map<String, String> filters) async {
    final response = await _apiClient.getJson(
      _path('/api/reports', filters),
      timeout: const Duration(seconds: 35),
    );
    if (response['data'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid report response.');
    }
    return BakeryReport.fromJson(response['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<ReportCategory>> categories() async {
    final response = await _apiClient.getJson('/api/reports/categories');
    final data = response['data'];
    if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid report categories.');
    }
    return data
        .map((item) => ReportCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<String> export(Map<String, String> filters, String format) async {
    if (format != 'CSV' && format != 'PDF') {
      throw const FormatException('Invalid export format.');
    }
    final path = _path('/api/reports/export', {...filters, 'format': format});
    final mimeType = format == 'CSV' ? 'text/csv' : 'application/pdf';
    final file = await _apiClient.getFile(path, contentType: mimeType);
    final saved = await _channel.invokeMethod<String>('saveToDownloads', {
      'filename': file.filename,
      'mimeType': mimeType,
      'bytes': file.bytes,
    });
    if (saved == null) throw const FormatException('Unable to save report.');
    return saved;
  }

  void close() => _apiClient.close();
}
