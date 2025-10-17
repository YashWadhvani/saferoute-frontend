import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {
  static String _resolveBaseUrl() {
    final apiUrl = dotenv.env['API_URL'];
    if (apiUrl != null && apiUrl.isNotEmpty) return apiUrl;
    final apiBase = dotenv.env['API_BASE_URL'];
    if (apiBase != null && apiBase.isNotEmpty) return apiBase;
    return 'https://saferoute-backend-nw9n.onrender.com/api/';
  }

  static final Dio dio = (() {
    final d = Dio(BaseOptions(
      baseUrl: _resolveBaseUrl(),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    // Attach a simple logging interceptor to help debug requests/responses.
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        try {
          debugPrint('HTTP Request -> ${options.method} ${options.uri}');
          if (options.data != null) debugPrint('Request body: ${options.data}');
        } catch (_) {}
        handler.next(options);
      },
      onResponse: (response, handler) {
        try {
          debugPrint('HTTP Response <- ${response.statusCode} ${response.requestOptions.uri}');
          debugPrint('Response body: ${response.data}');
        } catch (_) {}
        handler.next(response);
      },
      onError: (err, handler) {
        try {
          debugPrint('HTTP Error <- ${err.response?.statusCode} ${err.requestOptions.uri}');
          debugPrint('Error response: ${err.response?.data}');
        } catch (_) {}
        handler.next(err);
      },
    ));

    return d;
  })();
}
