import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/user_profile.dart';

class ProfileService {
  final Dio _dio = ApiClient.dio;

  ProfileService();

  Future<UserProfile?> fetchProfile() async {
    try {
      final r = await _dio.get('/api/user/profile');
      return UserProfile.fromMap(r.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> payload) async {
    try {
      await _dio.put('/api/user/profile', data: payload);
      return true;
    } catch (_) {
      return false;
    }
  }
}
