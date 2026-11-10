import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user_profile.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _sessionToken;
  UserProfile? _currentUser;

  String? get sessionToken => _sessionToken;
  UserProfile? get currentUser => _currentUser;
  bool get isAuthenticated => _sessionToken != null && _currentUser != null;

  /// Default API URL based on platform
  static String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:3333';
    }
    try {
      if (Platform.isAndroid) {
        // Android emulator loopback alias
        return 'http://10.0.2.2:3333';
      }
    } catch (_) {
      // In case Platform is unsupported on target
    }
    return 'http://localhost:3333';
  }

  String baseUrl = defaultBaseUrl;

  /// Register a new user with username and password
  Future<AuthResponse> register({
    required String username,
    required String password,
    required String displayName,
    String? email,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/auth/register');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
              'displayName': displayName,
              if (email != null && email.isNotEmpty) 'email': email,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        _sessionToken = data['token'] as String?;
        final profileJson = data['profile'] as Map<String, dynamic>;
        final userEmail = data['user']?['email'] as String?;
        _currentUser = UserProfile.fromJson(profileJson, email: userEmail);

        return AuthResponse.success(
          token: _sessionToken ?? '',
          profile: _currentUser!,
        );
      } else {
        final error = data['error'] as String? ?? 'Error al registrar el usuario';
        return AuthResponse.failure(error);
      }
    } catch (e) {
      return AuthResponse.failure('Error de conexión: $e');
    }
  }

  /// Login existing user with username and password
  Future<AuthResponse> login({
    required String username,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/auth/login');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _sessionToken = data['token'] as String?;
        final profileJson = data['profile'] as Map<String, dynamic>;
        final userEmail = data['user']?['email'] as String?;
        _currentUser = UserProfile.fromJson(profileJson, email: userEmail);

        return AuthResponse.success(
          token: _sessionToken ?? '',
          profile: _currentUser!,
        );
      } else {
        final error = data['error'] as String? ?? 'Credenciales incorrectas';
        return AuthResponse.failure(error);
      }
    } catch (e) {
      return AuthResponse.failure('Error de conexión: $e');
    }
  }

  /// Logout user
  void logout() {
    _sessionToken = null;
    _currentUser = null;
  }
}
