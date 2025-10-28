import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static String _resolveBaseUrl() {
    final apiUrl = dotenv.env['API_URL'];
    String? candidate;
    if (apiUrl != null && apiUrl.isNotEmpty) candidate = apiUrl;
    final apiBase = dotenv.env['API_BASE_URL'];
    if (candidate == null && apiBase != null && apiBase.isNotEmpty) candidate = apiBase;
    candidate ??= 'https://saferoute-backend-nw9n.onrender.com/api/';
    // Normalize: remove trailing '/api' segment if present so callers that
    // append '/api/...' don't create double segments.
    var normalized = candidate.replaceFirst(RegExp(r'/+api/?$'), '');
    // Ensure baseUrl always ends with a slash so relative paths concatenate
    // correctly (avoids "hostroutes/..." when callers omit a leading '/').
    if (!normalized.endsWith('/')) normalized = '$normalized/';
    return normalized;
  }

  static final Dio dio = (() {
    final d = Dio(BaseOptions(
      baseUrl: _resolveBaseUrl(),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    // Attach an interceptor that injects Authorization header from secure storage
    // and a simple logging interceptor to help debug requests/responses.
    final storage = const FlutterSecureStorage();
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await storage.read(key: 'token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
            if (kDebugMode) debugPrint('HTTP Request -> ${options.method} ${options.uri} [Authorization: set]');
          } else {
            if (kDebugMode) debugPrint('HTTP Request -> ${options.method} ${options.uri} [Authorization: none]');
          }
          if (options.data != null && kDebugMode) debugPrint('Request body: ${options.data}');
        } catch (e) {
          if (kDebugMode) debugPrint('HTTP Request prepare error: $e');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        try {
          if (kDebugMode) debugPrint('HTTP Response <- ${response.statusCode} ${response.requestOptions.uri}');
          if (kDebugMode) debugPrint('Response body: ${response.data}');
        } catch (_) {}
        handler.next(response);
      },
      onError: (err, handler) {
        try {
          if (kDebugMode) debugPrint('HTTP Error <- ${err.response?.statusCode} ${err.requestOptions.uri}');
          if (kDebugMode) debugPrint('Error response: ${err.response?.data}');
        } catch (_) {}
        handler.next(err);
      },
    ));

    return d;
  })();
}
