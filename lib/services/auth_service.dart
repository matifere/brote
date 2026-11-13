import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_item.dart';
import '../models/chat_message.dart';
import '../models/rating.dart';
import '../models/post_comment.dart';
import '../models/post_item.dart';
import '../models/report_item.dart';
import '../models/user_profile.dart';
import 'chat_crypto.dart';
import 'media_optimizer.dart';
import 'message_notification_service.dart';

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
  final ValueNotifier<int> postsRefreshNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> chatsRefreshNotifier = ValueNotifier<int>(0);

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

        // Automatic end-to-end chat encryption setup with account password
        try {
          await ChatCrypto().onAccountLogin(password);
        } catch (e) {
          debugPrint('Chat crypto auto-register warning: $e');
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

        // Automatic end-to-end chat encryption setup with account password
        try {
          await ChatCrypto().onAccountLogin(password);
        } catch (e) {
          debugPrint('Chat crypto auto-register warning: $e');
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

  /// Updates display name, bio description, avatar URL, banner URL, and privacy on Neon Cloud
  Future<AuthResponse> updateProfile({
    required String displayName,
    String? bio,
    String? avatarUrl,
    String? bannerUrl,
    bool? isPrivate,
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
              'bannerUrl': bannerUrl?.trim(),
              'isPrivate': ?isPrivate,
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

  /// Comments of a post, oldest first. Null when they can't be loaded, e.g. on
  /// servers that don't have comments yet.
  Future<List<PostComment>?> getComments(String postId) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/posts/$postId/comments');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['comments'] is List) {
          return (data['comments'] as List)
              .map((item) => PostComment.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching comments: $e');
    }
    return null;
  }

  /// Adds a comment or reply; returns it with the post's new comment count, or an error message.
  Future<({PostComment? comment, int? commentsCount, String? error})> addComment(
    String postId,
    String content, {
    String? parentId,
  }) async {
    final token = _sessionToken;
    if (token == null) return (comment: null, commentsCount: null, error: 'Sesión no iniciada');

    try {
      final uri = Uri.parse('$baseUrl/api/posts/$postId/comments');
      final payload = <String, dynamic>{
        'content': content.trim(),
        if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
      };
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true && data['comment'] != null) {
        return (
          comment: PostComment.fromJson(data['comment'] as Map<String, dynamic>),
          commentsCount: (data['commentsCount'] as num?)?.toInt(),
          error: null,
        );
      }
      return (comment: null, commentsCount: null, error: data['error'] as String? ?? 'No se pudo comentar');
    } catch (e) {
      debugPrint('Error adding comment: $e');
      return (comment: null, commentsCount: null, error: 'No se pudo comentar. Revisá tu conexión.');
    }
  }

  /// Toggles like on a comment. Returns whether it's liked and the new like count.
  Future<({bool success, bool isLiked, int likesCount, String? error})> toggleCommentLike(
    String postId,
    String commentId,
  ) async {
    final token = _sessionToken;
    if (token == null) return (success: false, isLiked: false, likesCount: 0, error: 'Sesión no iniciada');

    try {
      final uri = Uri.parse('$baseUrl/api/posts/$postId/comments/$commentId/like');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return (
          success: true,
          isLiked: data['isLiked'] == true,
          likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
          error: null,
        );
      }
      return (
        success: false,
        isLiked: false,
        likesCount: 0,
        error: data['error'] as String? ?? 'No se pudo actualizar el me gusta',
      );
    } catch (e) {
      debugPrint('Error toggling comment like: $e');
      return (success: false, isLiked: false, likesCount: 0, error: 'Error de conexión');
    }
  }

  /// Deletes a comment (yours, or any on your post). Returns the post's new comment count.
  Future<int?> deleteComment(String postId, String commentId) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/posts/$postId/comments/$commentId');
      final response = await http.delete(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return (data['commentsCount'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('Error deleting comment: $e');
    }
    return null;
  }

  /// Deletes one of your posts; feeds and profiles reload on success.
  Future<bool> deletePost(String postId) async {
    final token = _sessionToken;
    if (token == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/api/posts/$postId');
      final response = await http.delete(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && jsonDecode(response.body)['success'] == true) {
        postsRefreshNotifier.value++;
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting post: $e');
    }
    return false;
  }

  /// Applies a change to the ratings stored in the bio, keeping the rest of the profile intact
  Future<AuthResponse> updateBioRatings(ProfileBio Function(ProfileBio current) change) async {
    if (_sessionToken == null) {
      return AuthResponse.failure('Sesión no encontrada. Iniciá sesión nuevamente.');
    }

    // Start from the latest bio so edits made elsewhere aren't overwritten
    final latest = await fetchMyProfile();
    if (latest == null) {
      return AuthResponse.failure('No se pudo cargar tu perfil.');
    }

    final updated = change(ProfileBio.parse(latest.bio));
    if (!updated.fits) {
      return AuthResponse.failure(
        'No entra en tu descripción (máx. ${ProfileBio.maxLength} caracteres). '
        'Quitá alguna calificación o acortá tu biografía.',
      );
    }

    // avatarUrl and bannerUrl must be resent: the API clears them when they're null
    return updateProfile(
      displayName: latest.displayName,
      bio: updated.compose(),
      avatarUrl: latest.avatarUrl,
      bannerUrl: latest.bannerUrl,
    );
  }

  /// Follow a user on Neon (accepted if public, pending if private)
  Future<UserProfile?> followUser(String targetIdOrUsername) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/profile/$targetIdOrUsername/follow');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          return UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('Error following user: $e');
    }
    return null;
  }

  /// Unfollow a user or cancel a pending follow request
  Future<UserProfile?> unfollowUser(String targetIdOrUsername) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/profile/$targetIdOrUsername/unfollow');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          return UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('Error unfollowing user: $e');
    }
    return null;
  }

  /// Fetch full profile details for any user
  Future<UserProfile?> fetchUserProfile(String username) async {
    final token = _sessionToken;

    try {
      final uri = Uri.parse('$baseUrl/api/profile/$username');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          return UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
    return null;
  }

  /// Get pending follow requests for the authenticated user
  Future<List<FollowRequest>> getFollowRequests() async {
    final token = _sessionToken;
    if (token == null) return [];

    try {
      final uri = Uri.parse('$baseUrl/api/profile/me/follow-requests');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['requests'] is List) {
          final list = (data['requests'] as List)
              .map((item) => FollowRequest.fromJson(item as Map<String, dynamic>))
              .toList();
          if (_currentUser != null && _currentUser!.pendingRequestsCount != list.length) {
            _currentUser = _currentUser!.copyWith(pendingRequestsCount: list.length);
            currentUserNotifier.value = _currentUser;
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('Error fetching follow requests: $e');
    }
    return [];
  }

  /// Accept a follow request
  Future<bool> acceptFollowRequest(String followerId) async {
    final token = _sessionToken;
    if (token == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/api/profile/follow-requests/$followerId/accept');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (data['profile'] != null) {
            _currentUser = UserProfile.fromJson(data['profile'] as Map<String, dynamic>, email: _currentUser?.email);
          } else if (_currentUser != null) {
            _currentUser = _currentUser!.copyWith(
              followersCount: _currentUser!.followersCount + 1,
              pendingRequestsCount: (_currentUser!.pendingRequestsCount > 0)
                  ? _currentUser!.pendingRequestsCount - 1
                  : 0,
            );
          }
          currentUserNotifier.value = _currentUser;
          if (_currentUser != null) {
            await SessionStorage.save(token: token, profile: _currentUser!.toJson());
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error accepting follow request: $e');
    }
    return false;
  }

  /// Reject a follow request
  Future<bool> rejectFollowRequest(String followerId) async {
    final token = _sessionToken;
    if (token == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/api/profile/follow-requests/$followerId/reject');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (data['profile'] != null) {
            _currentUser = UserProfile.fromJson(data['profile'] as Map<String, dynamic>, email: _currentUser?.email);
          } else if (_currentUser != null) {
            _currentUser = _currentUser!.copyWith(
              pendingRequestsCount: (_currentUser!.pendingRequestsCount > 0)
                  ? _currentUser!.pendingRequestsCount - 1
                  : 0,
            );
          }
          currentUserNotifier.value = _currentUser;
          if (_currentUser != null) {
            await SessionStorage.save(token: token, profile: _currentUser!.toJson());
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error rejecting follow request: $e');
    }
    return false;
  }

  /// Uploads user avatar image from device to Neon server
  Future<AuthResponse> uploadAvatar(
    List<int> imageBytes, {
    String filename = 'avatar.jpg',
  }) async {
    final token = _sessionToken;
    if (token == null) {
      return AuthResponse.failure('Sesión no encontrada. Iniciá sesión nuevamente.');
    }

    try {
      final optimized = await MediaOptimizer.optimizeImage(
        Uint8List.fromList(imageBytes),
        maxWidth: 512,
        maxHeight: 512,
        quality: 80,
        filename: filename,
      );

      final uri = Uri.parse('$baseUrl/api/profile/avatar');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          optimized.bytes,
          filename: optimized.filename,
        ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final profileMap = data['profile'] as Map<String, dynamic>;
        _currentUser = UserProfile.fromJson(profileMap, email: _currentUser?.email);
        currentUserNotifier.value = _currentUser;
        await SessionStorage.save(token: token, profile: _currentUser!.toJson());

        return AuthResponse.success(token: token, profile: _currentUser!);
      } else {
        final error = data['error'] as String? ?? 'Error al subir la imagen al servidor';
        return AuthResponse.failure(error);
      }
    } catch (e) {
      return AuthResponse.failure('Error al conectar con el servidor: $e');
    }
  }

  /// Uploads user banner cover image from device to Neon server
  Future<AuthResponse> uploadBanner(
    List<int> imageBytes, {
    String filename = 'banner.jpg',
  }) async {
    final token = _sessionToken;
    if (token == null) {
      return AuthResponse.failure('Sesión no encontrada. Iniciá sesión nuevamente.');
    }

    try {
      final optimized = await MediaOptimizer.optimizeImage(
        Uint8List.fromList(imageBytes),
        maxWidth: 1280,
        maxHeight: 720,
        quality: 80,
        filename: filename,
      );

      final uri = Uri.parse('$baseUrl/api/profile/banner');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          optimized.bytes,
          filename: optimized.filename,
        ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final profileMap = data['profile'] as Map<String, dynamic>;
        _currentUser = UserProfile.fromJson(profileMap, email: _currentUser?.email);
        currentUserNotifier.value = _currentUser;
        await SessionStorage.save(token: token, profile: _currentUser!.toJson());

        return AuthResponse.success(token: token, profile: _currentUser!);
      } else {
        final error = data['error'] as String? ?? 'Error al subir el banner al servidor';
        return AuthResponse.failure(error);
      }
    } catch (e) {
      return AuthResponse.failure('Error al conectar con el servidor: $e');
    }
  }

  /// Search real user profiles on Neon by username or display name
  Future<List<UserProfile>> searchProfiles(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final uri = Uri.parse('$baseUrl/api/profiles/search?q=${Uri.encodeComponent(cleanQuery)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['results'] is List) {
          final list = data['results'] as List;
          return list
              .map((item) => UserProfile.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error searching profiles: $e');
    }
    return [];
  }

  /// Get suggested real user profiles for discovery
  Future<List<UserProfile>> getSuggestedProfiles() async {
    try {
      final uri = Uri.parse('$baseUrl/api/profiles/suggested');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['results'] is List) {
          final list = data['results'] as List;
          return list
              .map((item) => UserProfile.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching suggested profiles: $e');
    }
    return [];
  }

  /// Uploads post image from device to Neon Object Storage with client-side compression
  Future<String?> uploadPostImage(
    List<int> imageBytes, {
    String filename = 'post.jpg',
  }) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final optimized = await MediaOptimizer.optimizeImage(
        Uint8List.fromList(imageBytes),
        maxWidth: 1280,
        maxHeight: 1280,
        quality: 78,
        filename: filename,
      );

      final uri = Uri.parse('$baseUrl/api/posts/upload-image');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          optimized.bytes,
          filename: optimized.filename,
        ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return data['imageUrl'] as String?;
      }
    } catch (e) {
      debugPrint('Error uploading post image: $e');
    }
    return null;
  }

  /// Uploads post video from device to Neon Object Storage
  Future<String?> uploadPostVideo(
    List<int> videoBytes, {
    String filename = 'video.mp4',
  }) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/posts/upload-video');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          videoBytes,
          filename: filename,
        ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return data['videoUrl'] as String?;
      } else {
        lastCreatePostError = data['error'] as String?;
      }
    } catch (e) {
      debugPrint('Error uploading post video: $e');
    }
    return null;
  }

  String? lastCreatePostError;

  /// Creates a new publication (plain text, markdown, images, video or text with media)
  Future<PostItem?> createPost({
    String? content,
    String? imageUrl,
    List<String>? imageUrls,
    String? videoUrl,
    bool isSensitive = false,
  }) async {
    lastCreatePostError = null;
    final token = _sessionToken;
    if (token == null) {
      lastCreatePostError = 'No has iniciado sesión';
      return null;
    }

    final resolvedImages = (imageUrls != null && imageUrls.isNotEmpty)
        ? imageUrls
        : (imageUrl != null && imageUrl.trim().isNotEmpty ? [imageUrl.trim()] : null);
    final primaryImage = resolvedImages?.isNotEmpty == true ? resolvedImages!.first : imageUrl?.trim();

    try {
      final uri = Uri.parse('$baseUrl/api/posts');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'content': content?.trim(),
          'imageUrl': primaryImage,
          'imageUrls': resolvedImages,
          'videoUrl': videoUrl?.trim(),
          'isSensitive': isSensitive,
        }),
      ).timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true && data['post'] != null) {
        postsRefreshNotifier.value++;
        return PostItem.fromJson(data['post'] as Map<String, dynamic>);
      } else {
        lastCreatePostError = data['error'] as String? ?? 'Error al publicar';
      }
    } catch (e) {
      debugPrint('Error creating post: $e');
      lastCreatePostError = e.toString();
    }
    return null;
  }

  /// Sends a report against a post, comment or user
  Future<({bool success, String message, String? error})> reportContent({
    String? postId,
    String? commentId,
    String? userId,
    required String reason,
    String? details,
  }) async {
    final token = _sessionToken;
    if (token == null) return (success: false, message: '', error: 'No autorizado');

    try {
      final uri = Uri.parse('$baseUrl/api/reports');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'postId': postId,
          'commentId': commentId,
          'userId': userId,
          'reason': reason,
          'details': details,
        }),
      ).timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return (
          success: true,
          message: data['message'] as String? ?? 'Reporte enviado con éxito',
          error: null,
        );
      }
      return (
        success: false,
        message: '',
        error: data['error'] as String? ?? 'No se pudo enviar el reporte',
      );
    } catch (e) {
      return (success: false, message: '', error: e.toString());
    }
  }

  /// Blocks a user
  Future<bool> blockUser(String userId) async {
    final token = _sessionToken;
    if (token == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/api/users/$userId/block');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        postsRefreshNotifier.value++;
        return true;
      }
    } catch (e) {
      debugPrint('Error blocking user: $e');
    }
    return false;
  }

  /// Unblocks a user
  Future<bool> unblockUser(String userId) async {
    final token = _sessionToken;
    if (token == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/api/users/$userId/block');
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        postsRefreshNotifier.value++;
        return true;
      }
    } catch (e) {
      debugPrint('Error unblocking user: $e');
    }
    return false;
  }

  /// Fetches reports for admin / moderator dashboard
  Future<List<ReportItem>> getAdminReports({String status = 'pending'}) async {
    final token = _sessionToken;
    if (token == null) return const [];

    try {
      final uri = Uri.parse('$baseUrl/api/admin/reports?status=$status');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['reports'] is List) {
          return (data['reports'] as List)
              .map((r) => ReportItem.fromJson(r as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching admin reports: $e');
    }
    return const [];
  }

  /// Performs a moderation action on a report (dismiss, hide, delete, suspend)
  Future<bool> takeAdminReportAction(String reportId, String action) async {
    final token = _sessionToken;
    if (token == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/api/admin/reports/$reportId/action');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'action': action}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('Error taking admin report action: $e');
    }
    return false;
  }

  /// Fetches feed posts from Neon
  Future<List<PostItem>> getFeedPosts({String? filter}) async {
    final token = _sessionToken;

    try {
      final queryParam = (filter != null && filter.isNotEmpty) ? '?filter=$filter' : '';
      final uri = Uri.parse('$baseUrl/api/posts/feed$queryParam');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['posts'] is List) {
          final list = data['posts'] as List;
          return list
              .map((item) => PostItem.fromJson(item as Map<String, dynamic>))
              .where((post) => !post.isExpired)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching feed posts: $e');
    }
    return [];
  }

  /// Fetches posts for a specific user
  Future<List<PostItem>> getUserPosts(String usernameOrId) async {
    final token = _sessionToken;

    try {
      final uri = Uri.parse('$baseUrl/api/posts/user/$usernameOrId');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['posts'] is List) {
          final list = data['posts'] as List;
          return list
              .map((item) => PostItem.fromJson(item as Map<String, dynamic>))
              .where((post) => !post.isExpired)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching user posts: $e');
    }
    return [];
  }

  /// Toggles like on a post
  Future<Map<String, dynamic>?> toggleLikePost(String postId) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/posts/$postId/like');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true) {
          return {
            'isLiked': data['isLiked'] as bool? ?? false,
            'likesCount': (data['likesCount'] as num? ?? 0).toInt(),
          };
        }
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
    return null;
  }

  /// Fetches all active conversations for the authenticated user
  Future<List<ChatItem>> getConversations() async {
    final token = _sessionToken;
    if (token == null) return [];

    try {
      final uri = Uri.parse('$baseUrl/api/chats');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['chats'] is List) {
          final list = data['chats'] as List;
          return list.map((item) => ChatItem.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching conversations: $e');
    }
    return [];
  }

  /// Starts or gets existing conversation with a user (handles privacy restrictions)
  Future<Map<String, dynamic>> startConversationWithUser(
    String targetUserId, {
    String? initialMessage,
  }) async {
    final token = _sessionToken;
    if (token == null) {
      return {'success': false, 'error': 'No hay sesión activa.'};
    }

    try {
      final uri = Uri.parse('$baseUrl/api/chats/with/$targetUserId');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          if (initialMessage != null && initialMessage.trim().isNotEmpty)
            'initialMessage': initialMessage.trim(),
        }),
      ).timeout(const Duration(seconds: 12));

      final Map<String, dynamic> data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        chatsRefreshNotifier.value++;
        UserProfile? other;
        if (data['otherParticipant'] != null) {
          other = UserProfile.fromJson(data['otherParticipant'] as Map<String, dynamic>);
        }
        return {
          'success': true,
          'conversationId': data['conversationId']?.toString(),
          'otherParticipant': other,
        };
      } else {
        return {
          'success': false,
          'error': data['error'] as String? ?? 'Error al iniciar la conversación',
          'isPrivateRestricted': data['isPrivateRestricted'] as bool? ?? false,
        };
      }
    } catch (e) {
      debugPrint('Error starting conversation: $e');
      return {'success': false, 'error': 'Error de conexión: $e'};
    }
  }

  /// Fetches messages and other participant info for a conversation
  Future<Map<String, dynamic>?> getConversationMessages(String conversationId) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/chats/$conversationId/messages');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['messages'] is List) {
          final msgs = (data['messages'] as List)
              .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
              .toList();
          UserProfile? other;
          if (data['otherParticipant'] != null) {
            other = UserProfile.fromJson(data['otherParticipant'] as Map<String, dynamic>);
          }
          return {
            'messages': msgs,
            'otherParticipant': other,
          };
        }
      }
    } catch (e) {
      debugPrint('Error fetching conversation messages: $e');
    }
    return null;
  }

  /// Sends a message in a conversation (handles privacy restrictions and auto-retries on cold start)
  Future<Map<String, dynamic>> sendMessage(
    String conversationId, {
    String? content,
    String? mediaUrl,
  }) async {
    final token = _sessionToken;
    if (token == null) {
      return {'success': false, 'error': 'Sesión no iniciada'};
    }

    final uri = Uri.parse('$baseUrl/api/chats/$conversationId/messages');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = jsonEncode({
      'content': content?.trim(),
      'mediaUrl': mediaUrl?.trim(),
    });

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 25));

        final Map<String, dynamic> data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success'] == true && data['message'] != null) {
          chatsRefreshNotifier.value++;
          return {
            'success': true,
            'message': ChatMessage.fromJson(data['message'] as Map<String, dynamic>),
          };
        } else {
          return {
            'success': false,
            'error': data['error'] as String? ?? 'Error al enviar el mensaje',
            'isPrivateRestricted': data['isPrivateRestricted'] as bool? ?? false,
          };
        }
      } catch (e) {
        if (attempt == 0) {
          debugPrint('Attempt $attempt sending message failed ($e), retrying after short wait...');
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
        debugPrint('Error sending message: $e');
        return {'success': false, 'error': 'Error de conexión: $e'};
      }
    }

    return {'success': false, 'error': 'Error de conexión al enviar el mensaje'};
  }

  /// Uploads an image attached to a chat to Neon Object Storage with client-side compression
  Future<String?> uploadChatImage(
    List<int> imageBytes, {
    String filename = 'chat.jpg',
  }) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final optimized = await MediaOptimizer.optimizeImage(
        Uint8List.fromList(imageBytes),
        maxWidth: 1280,
        maxHeight: 1280,
        quality: 78,
        filename: filename,
      );

      final uri = Uri.parse('$baseUrl/api/chats/upload-image');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          optimized.bytes,
          filename: optimized.filename,
        ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final url = data['imageUrl'] as String?;
        // The chat upload endpoint answers with a server-relative path
        // (`/api/posts/media/...`); store an absolute URL so every client can load it.
        if (url != null && url.startsWith('/')) return '$baseUrl$url';
        return url;
      }
      debugPrint('Chat image upload failed (${response.statusCode}): ${data['error']}');
    } catch (e) {
      debugPrint('Error uploading chat image: $e');
    }
    return null;
  }

  /// Fetches candidate users to start a chat with, indicating privacy permissions
  Future<List<ChatCandidate>> getChatCandidates({String query = ''}) async {
    final token = _sessionToken;
    if (token == null) return [];

    try {
      final uri = Uri.parse('$baseUrl/api/chats/candidates?q=${Uri.encodeComponent(query.trim())}');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['candidates'] is List) {
          final list = data['candidates'] as List;
          return list.map((item) => ChatCandidate.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching chat candidates: $e');
    }
    return [];
  }

  /// Logout user and clear stored credentials on device
  Future<void> logout() async {
    _sessionToken = null;
    _currentUser = null;
    currentUserNotifier.value = null;
    await SessionStorage.clear();
    // The chat key backup stays on the server; only this device's copy is removed
    await ChatCrypto().clear();
    MessageNotificationService().stop();
  }
}
