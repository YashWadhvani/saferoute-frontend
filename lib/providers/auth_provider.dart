import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  Future<void> sendOtp(String contact) async {
    await _authService.sendOtp(contact);
  }

  Future<void> verifyOtp(String contact, String otp) async {
    final token = await _authService.verifyOtp(contact, otp);
    await _storage.write(key: 'token', value: token);
    // record last login time
    await _storage.write(key: 'lastLogin', value: DateTime.now().toIso8601String());
    _isLoggedIn = true;
    notifyListeners();
  }

  /// Checks persisted token and lastLogin time. Returns true if token exists and last login was within [days] days.
  Future<bool> checkRecentLogin({int days = 7}) async {
    final token = await _storage.read(key: 'token');
    if (token == null || token.isEmpty) return false;
    final last = await _storage.read(key: 'lastLogin');
    if (last == null) return false;
    try {
      final dt = DateTime.parse(last);
      if (DateTime.now().difference(dt).inDays <= days) {
        _isLoggedIn = true;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Clear login state
  Future<void> logout() async {
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'lastLogin');
    _isLoggedIn = false;
    notifyListeners();
  }
}
