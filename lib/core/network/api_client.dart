import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, SupabaseClient? supabaseClient})
    : _httpClient = httpClient ?? http.Client(),
      _supabase = supabaseClient ?? Supabase.instance.client;

  final http.Client _httpClient;
  final SupabaseClient _supabase;

  Future<Map<String, dynamic>> getJson(String path) {
    return _send(method: 'GET', path: path);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) {
    return _send(method: 'POST', path: path, body: body);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) {
    return _send(method: 'PATCH', path: path, body: body);
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final session = _supabase.auth.currentSession;

    if (session == null) {
      throw const ApiException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'Please sign in to continue.',
      );
    }

    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/$'), '');

    final uri = Uri.parse('$baseUrl$path');

    final headers = {
      'Authorization': 'Bearer ${session.accessToken}',
      'Content-Type': 'application/json',
    };

    try {
      late final http.Response response;

      if (method == 'GET') {
        response = await _httpClient
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
      } else if (method == 'POST') {
        response = await _httpClient
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
      } else if (method == 'PATCH') {
        response = await _httpClient
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
      } else {
        throw ArgumentError('Unsupported HTTP method.');
      }

      return _decodeResponse(response);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 503,
        code: 'REQUEST_TIMEOUT',
        message: 'The server took too long to respond.',
      );
    } on http.ClientException {
      throw const ApiException(
        statusCode: 503,
        code: 'SERVER_UNAVAILABLE',
        message: 'Unable to connect to the server.',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic>? json;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } on FormatException {
      json = null;
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        json != null) {
      return json;
    }

    final error = json?['error'];

    if (error is Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        code: error['code'] is String
            ? error['code'] as String
            : 'REQUEST_FAILED',
        message: error['message'] is String
            ? error['message'] as String
            : 'The request failed.',
      );
    }

    throw ApiException(
      statusCode: response.statusCode,
      code: 'INVALID_SERVER_RESPONSE',
      message: 'The server returned an invalid response.',
    );
  }

  void close() {
    _httpClient.close();
  }
}
