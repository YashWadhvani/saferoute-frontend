import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {
  static String _resolveBaseUrl() {
    final apiUrl = dotenv.env['API_URL'];
    if (apiUrl != null && apiUrl.isNotEmpty) return apiUrl;
    final apiBase = dotenv.env['API_BASE_URL'];
    if (apiBase != null && apiBase.isNotEmpty) return apiBase;
    return 'http://10.0.2.2:5000';
  }

  static final Dio dio = Dio(BaseOptions(
    baseUrl: _resolveBaseUrl(),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));
}
