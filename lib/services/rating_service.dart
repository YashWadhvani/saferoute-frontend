import 'package:dio/dio.dart';
import '../core/api_client.dart';

class RatingService {
  final Dio _dio = ApiClient.dio;

  RatingService();

  Future<bool> submitRouteFeedback(Map<String, dynamic> payload) async {
    try {
      await _dio.post('/api/route-feedback', data: payload);
      return true;
    } catch (_) {
      return false;
    }
  }
}
