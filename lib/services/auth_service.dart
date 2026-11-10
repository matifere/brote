import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_item.dart';
import '../models/chat_message.dart';
import '../models/post_item.dart';
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
            _currentUser = UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
          } else if (_currentUser != null) {
            _currentUser = _currentUser!.copyWith(
              followersCount: _currentUser!.followersCount + 1,
              pendingRequestsCount: (_currentUser!.pendingRequestsCount > 0)
                  ? _currentUser!.pendingRequestsCount - 1
                  : 0,
            );
          }
          currentUserNotifier.value = _currentUser;
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
            _currentUser = UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
          } else if (_currentUser != null) {
            _currentUser = _currentUser!.copyWith(
              pendingRequestsCount: (_currentUser!.pendingRequestsCount > 0)
                  ? _currentUser!.pendingRequestsCount - 1
                  : 0,
            );
          }
          currentUserNotifier.value = _currentUser;
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
      final uri = Uri.parse('$baseUrl/api/profile/avatar');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: filename,
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
      final uri = Uri.parse('$baseUrl/api/profile/banner');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: filename,
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

  /// Uploads post image from device to Neon Object Storage
  Future<String?> uploadPostImage(
    List<int> imageBytes, {
    String filename = 'post.jpg',
  }) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/posts/upload-image');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: filename,
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

  /// Creates a new publication (plain text, markdown, image or text with image)
  Future<PostItem?> createPost({
    String? content,
    String? imageUrl,
  }) async {
    final token = _sessionToken;
    if (token == null) return null;

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
          'imageUrl': imageUrl?.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true && data['post'] != null) {
        postsRefreshNotifier.value++;
        return PostItem.fromJson(data['post'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Error creating post: $e');
    }
    return null;
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
          return list.map((item) => PostItem.fromJson(item as Map<String, dynamic>)).toList();
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
          return list.map((item) => PostItem.fromJson(item as Map<String, dynamic>)).toList();
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
      ).timeout(const Duration(seconds: 10));

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
      ).timeout(const Duration(seconds: 10));

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

  /// Sends a message in a conversation (handles privacy restrictions)
  Future<Map<String, dynamic>> sendMessage(
    String conversationId, {
    String? content,
    String? mediaUrl,
  }) async {
    final token = _sessionToken;
    if (token == null) {
      return {'success': false, 'error': 'Sesión no iniciada'};
    }

    try {
      final uri = Uri.parse('$baseUrl/api/chats/$conversationId/messages');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'content': content?.trim(),
          'mediaUrl': mediaUrl?.trim(),
        }),
      ).timeout(const Duration(seconds: 12));

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
      debugPrint('Error sending message: $e');
      return {'success': false, 'error': 'Error de conexión: $e'};
    }
  }

  /// Uploads an image attached to a chat to Neon Object Storage
  Future<String?> uploadChatImage(
    List<int> imageBytes, {
    String filename = 'chat.jpg',
  }) async {
    final token = _sessionToken;
    if (token == null) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/chats/upload-image');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: filename,
        ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return data['imageUrl'] as String?;
      }
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
  }
}
