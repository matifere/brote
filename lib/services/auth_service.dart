import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class SessionStorage {
  static const String _kTokenKey = 'brote_session_token';
  static const String _kProfileKey = 'brote_user_profile';

  static File? _getFallbackFile() {
    if (kIsWeb) return null;
    try {
      if (Platform.isAndroid) {
        return File('/data/data/com.example.brote/session.json');
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save({required String token, required Map<String, dynamic> profile}) async {
    // 1. SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, token);
      await prefs.setString(_kProfileKey, jsonEncode(profile));
    } catch (e) {
      debugPrint('SharedPreferences save notice (may require full rebuild): $e');
    }

    // 2. Direct sandbox file fallback (guarantees persistence even without native plugin compilation)
    try {
      final file = _getFallbackFile();
      if (file != null) {
        await file.writeAsString(jsonEncode({'token': token, 'profile': profile}), flush: true);
      }
    } catch (e) {
      debugPrint('Sandbox file save notice: $e');
    }
  }

  static Future<Map<String, dynamic>?> load() async {
    // 1. Try SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kTokenKey);
      final profileStr = prefs.getString(_kProfileKey);
      if (token != null && profileStr != null) {
        return {
          'token': token,
          'profile': jsonDecode(profileStr) as Map<String, dynamic>,
        };
      }
    } catch (e) {
      debugPrint('SharedPreferences load notice: $e');
    }

    // 2. Try direct sandbox file fallback
    try {
      final file = _getFallbackFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          return {
            'token': data['token'] as String,
            'profile': data['profile'] as Map<String, dynamic>,
          };
        }
      }
    } catch (e) {
      debugPrint('Sandbox file load notice: $e');
    }

    return null;
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTokenKey);
      await prefs.remove(_kProfileKey);
    } catch (_) {}

    try {
      final file = _getFallbackFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Dedicated cloud server on Neon Functions
  static const String neonServerUrl =
      'https://br-spring-base-betng0ba-api.compute.c-9.us-east-2.aws.neon.tech';

  String get baseUrl => neonServerUrl;

  String? _sessionToken;
  UserProfile? _currentUser;
  final ValueNotifier<UserProfile?> currentUserNotifier = ValueNotifier<UserProfile?>(null);

  String? get sessionToken => _sessionToken;
  UserProfile? get currentUser => _currentUser;
  bool get isAuthenticated => _sessionToken != null && _currentUser != null;

  /// Restores session from persistent storage on device
  Future<bool> tryAutoLogin() async {
    try {
      final savedData = await SessionStorage.load();
      if (savedData == null) {
        return false;
      }

      final token = savedData['token'] as String?;
      final profileMap = savedData['profile'] as Map<String, dynamic>?;

      if (token == null || profileMap == null) {
        return false;
      }

      // Restore session in memory immediately
      _sessionToken = token;
      _currentUser = UserProfile.fromJson(profileMap, email: profileMap['email'] as String?);
      currentUserNotifier.value = _currentUser;

      // Verify and update profile with Neon in background
      _verifyTokenWithNeon(token).then((isValid) {
        if (!isValid) {
          logout();
        }
      }).catchError((_) {
        // Keep cached session if offline
      });

      return true;
    } catch (e) {
      debugPrint('Error restoring session: $e');
      return false;
    }
  }

  Future<bool> _verifyTokenWithNeon(String token) async {
    try {
      final uri = Uri.parse('$baseUrl/api/auth/me');
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['profile'] != null) {
          final profileJson = data['profile'] as Map<String, dynamic>;
          final userEmail = data['user']?['email'] as String?;
          _currentUser = UserProfile.fromJson(profileJson, email: userEmail);
          currentUserNotifier.value = _currentUser;
          await SessionStorage.save(token: token, profile: _currentUser!.toJson());
          return true;
        }
      } else if (res.statusCode == 401) {
        // Session expired on server
        return false;
      }
    } catch (_) {
      // Offline / network issue: don't logout, allow cached use
    }
    return true;
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
          .timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        _sessionToken = data['token'] as String?;
        final profileJson = data['profile'] as Map<String, dynamic>;
        final userEmail = data['user']?['email'] as String?;
        _currentUser = UserProfile.fromJson(profileJson, email: userEmail);
        currentUserNotifier.value = _currentUser;

        if (_sessionToken != null && _currentUser != null) {
          await SessionStorage.save(token: _sessionToken!, profile: _currentUser!.toJson());
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
      return AuthResponse.failure('Error al conectar con Neon: $e');
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
          .timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _sessionToken = data['token'] as String?;
        final profileJson = data['profile'] as Map<String, dynamic>;
        final userEmail = data['user']?['email'] as String?;
        _currentUser = UserProfile.fromJson(profileJson, email: userEmail);
        currentUserNotifier.value = _currentUser;

        if (_sessionToken != null && _currentUser != null) {
          await SessionStorage.save(token: _sessionToken!, profile: _currentUser!.toJson());
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
      return AuthResponse.failure('Error al conectar con Neon: $e');
    }
  }

  /// Fetches and refreshes the current user's profile from Neon Cloud
  Future<UserProfile?> fetchMyProfile() async {
    final token = _sessionToken;
    if (token == null) return _currentUser;

    try {
      final uri = Uri.parse('$baseUrl/api/profile/me');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          final profileMap = data['profile'] as Map<String, dynamic>;
          _currentUser = UserProfile.fromJson(profileMap, email: _currentUser?.email);
          currentUserNotifier.value = _currentUser;
          await SessionStorage.save(token: token, profile: _currentUser!.toJson());
          return _currentUser;
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
    return _currentUser;
  }

  /// Updates display name, bio description, and avatar URL on Neon Cloud
  Future<AuthResponse> updateProfile({
    required String displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    final token = _sessionToken;
    if (token == null) {
      return AuthResponse.failure('Sesión no encontrada. Iniciá sesión nuevamente.');
    }

    try {
      final uri = Uri.parse('$baseUrl/api/profile/me');
      final response = await http
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'displayName': displayName.trim(),
              'bio': bio?.trim(),
              'avatarUrl': avatarUrl?.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final profileMap = data['profile'] as Map<String, dynamic>;
        _currentUser = UserProfile.fromJson(profileMap, email: _currentUser?.email);
        currentUserNotifier.value = _currentUser;
        await SessionStorage.save(token: token, profile: _currentUser!.toJson());

        return AuthResponse.success(token: token, profile: _currentUser!);
      } else {
        final error = data['error'] as String? ?? 'Error al actualizar el perfil';
        return AuthResponse.failure(error);
      }
    } catch (e) {
      return AuthResponse.failure('Error al conectar con Neon: $e');
    }
  }

  /// Logout user and clear stored credentials on device
  Future<void> logout() async {
    _sessionToken = null;
    _currentUser = null;
    currentUserNotifier.value = null;
    await SessionStorage.clear();
  }
}
