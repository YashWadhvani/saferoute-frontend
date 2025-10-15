import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  final Dio _dio = Dio();
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? "http://10.0.2.2:5000"; // change if deployed or on LAN

  Future<void> sendOtp(String identifier) async {
    try {
      final response = await _dio.post(
        '$baseUrl/auth/send-otp',
        data: {'identifier': identifier},
      );
  debugPrint('OTP sent: ${response.data}');
    } on DioException catch (e) {
  debugPrint('Error sending OTP: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  Future<String> verifyOtp(String identifier, String otp) async {
    try {
      final response = await _dio.post(
        '$baseUrl/auth/verify-otp',
        data: {'identifier': identifier, 'otp': otp},
      );
  // Log full response for debugging
  debugPrint('OTP verified: ${response.data}');

      // Try common token keys returned by typical auth endpoints
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final token = data['token'] ?? data['accessToken'] ?? data['access_token'];
        if (token is String) return token;
        // Sometimes token is nested under a 'data' key
        if (data['data'] is Map<String, dynamic>) {
          final nested = data['data'] as Map<String, dynamic>;
          final nestedToken = nested['token'] ?? nested['accessToken'] ?? nested['access_token'];
          if (nestedToken is String) return nestedToken;
        }
        // Fallback to stringifying the whole response
        return data.toString();
      }

      // If response.data isn't a map, return its string representation
      return data.toString();
    } on DioException catch (e) {
  debugPrint('Error verifying OTP: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }
}
