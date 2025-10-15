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
    _isLoggedIn = true;
    notifyListeners();
  }
}
