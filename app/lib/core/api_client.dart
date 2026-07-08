import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper over Dio. The API base URL is injected at build time with
/// --dart-define=API_BASE_URL=... ; in the Docker deployment nginx proxies
/// /api to the backend so the default relative base works out of the box.
class ApiClient {
  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kIsWeb ? '' : 'http://localhost:8080',
  );

  late final Dio _dio;
  String? _token;

  set token(String? value) => _token = value;
  String? get token => _token;

  Options get _auth => Options(headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      });

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final res = await _dio.get(path, queryParameters: query, options: _auth);
    return res.data;
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final res = await _dio.post(path, data: body, options: _auth);
    return res.data;
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final res = await _dio.patch(path, data: body, options: _auth);
    return res.data;
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final res = await _dio.put(path, data: body, options: _auth);
    return res.data;
  }

  Future<dynamic> delete(String path) async {
    final res = await _dio.delete(path, options: _auth);
    return res.data;
  }

  Future<dynamic> upload(String path, MultipartFile file) async {
    final res = await _dio.post(
      path,
      data: FormData.fromMap({'file': file}),
      options: _auth,
    );
    return res.data;
  }

  /// URL for browser-download endpoints (exports, files) with token attached.
  String downloadUrl(String path) {
    final sep = path.contains('?') ? '&' : '?';
    return '$baseUrl$path${sep}token=$_token';
  }

  static String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        return data['error']['message']?.toString() ?? 'Request failed';
      }
      return error.message ?? 'Network error';
    }
    return error.toString();
  }
}
