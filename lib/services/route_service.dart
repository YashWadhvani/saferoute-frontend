import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';

class RouteService {
  static Future<dynamic> compareRoutes(Map<String, dynamic> payload) async {
    try {
      final bodyText = jsonEncode(payload);
      debugPrint('RouteService -> final JSON payload: $bodyText');

      final resp = await ApiClient.dio.post(
        'routes/compare',
        data: bodyText,
        options: Options(
          headers: {'Content-Type': 'application/json'}, // ensure header
        ),
      );
      return resp.data;
    } catch (e) {
      if (e is DioException) {
        final resp = e.response;
        debugPrint('RouteService.compareRoutes error status: ${resp?.statusCode}, data: ${resp?.data}');
        rethrow;
      }
      rethrow;
    }
  }
}
