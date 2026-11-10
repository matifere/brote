import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _kTokenKey = 'brote_session_token';
  static const String _kProfileKey = 'brote_user_profile';

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
        return 'http://10.0.2.2:3333';
      }
    } catch (_) {
      // In case Platform is unsupported on target
    }
    return 'http://localhost:3333';
  }

  String baseUrl = defaultBaseUrl;

  /// Restores session from persistent device storage
  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kTokenKey);
      final profileStr = prefs.getString(_kProfileKey);

      if (token == null || profileStr == null) {
        return false;
      }

      // Restore locally cached session immediately
      _sessionToken = token;
      final profileMap = jsonDecode(profileStr) as Map<String, dynamic>;
      _currentUser = UserProfile.fromJson(profileMap, email: profileMap['email'] as String?);

      // Verify token with backend in background
      _verifyTokenWithBackend(token).then((isValid) {
        if (!isValid) {
          logout();
        }
      }).catchError((_) {
        // If offline, keep local session
      });

      return true;
    } catch (e) {
      debugPrint('Error restoring session: $e');
      return false;
    }
  }

  Future<bool> _verifyTokenWithBackend(String token) async {
    try {
      final uri = Uri.parse('$baseUrl/api/auth/me');
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['profile'] != null) {
          final profileJson = data['profile'] as Map<String, dynamic>;
          final userEmail = data['user']?['email'] as String?;
          _currentUser = UserProfile.fromJson(profileJson, email: userEmail);
          await _saveSession(token, _currentUser!);
          return true;
        }
      } else if (res.statusCode == 401) {
        // Session expired or revoked on server
        return false;
      }
    } catch (_) {
      // Network timeout / offline -> keep cached session
    }
    return true;
  }

  Future<void> _saveSession(String token, UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, token);
      await prefs.setString(_kProfileKey, jsonEncode(profile.toJson()));
    } catch (e) {
      debugPrint('Error saving session: $e');
    }
  }

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

        if (_sessionToken != null && _currentUser != null) {
          await _saveSession(_sessionToken!, _currentUser!);
        }

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

        if (_sessionToken != null && _currentUser != null) {
          await _saveSession(_sessionToken!, _currentUser!);
        }

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

  /// Logout user and clear stored credentials
  Future<void> logout() async {
    _sessionToken = null;
    _currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTokenKey);
      await prefs.remove(_kProfileKey);
    } catch (e) {
      debugPrint('Error clearing session: $e');
    }
  }
}
