import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_item.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';

enum FollowListType { followers, following }

class FollowListResult {
  final List<UserProfile> users;

  /// The account is private and the viewer is not an accepted follower.
  final bool locked;

  /// The server can't provide this list yet (no followers/following endpoint
  /// deployed and it isn't the viewer's own profile).
  final bool unavailable;

  const FollowListResult({
    this.users = const [],
    this.locked = false,
    this.unavailable = false,
  });
}

class FollowService {
  static final FollowService _instance = FollowService._internal();
  factory FollowService() => _instance;
  FollowService._internal();

  /// Matches the LIMIT of GET /api/chats/candidates.
  static const int _candidatesPageSize = 20;

  Future<FollowListResult> fetch(UserProfile profile, FollowListType type) async {
    final auth = AuthService();
    final token = auth.sessionToken;
    final path = type == FollowListType.followers ? 'followers' : 'following';

    // 1. Dedicated endpoint (GET /api/profile/:target/followers|following).
    try {
      final uri = Uri.parse(
        '${auth.baseUrl}/api/profile/${Uri.encodeComponent(profile.username)}/$path',
      );
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['success'] == true && data['users'] is List) {
          final users = (data['users'] as List)
              .map((item) => UserProfile.fromJson(item as Map<String, dynamic>))
              .toList();
          return FollowListResult(users: users);
        }
      } else if (response.statusCode == 403) {
        return const FollowListResult(locked: true);
      }
    } catch (e) {
      debugPrint('Error fetching $path list: $e');
    }

    // 2. Fallback while that endpoint isn't deployed: the chat candidates
    // endpoint flags, for every user, whether the viewer follows them and
    // whether they follow the viewer. That only describes the viewer's own
    // relationships, so it can't be used for someone else's profile.
    if (token == null || auth.currentUser?.id != profile.id) {
      return const FollowListResult(unavailable: true);
    }

    final candidates = await _allChatCandidates();
    final users = candidates
        .where((c) => type == FollowListType.followers ? c.isFollower : c.isFollowing)
        .map(
          (c) => UserProfile(
            id: c.id,
            username: c.username,
            displayName: c.displayName,
            avatarUrl: c.avatarUrl,
            isVerified: c.isVerified,
            isPrivate: c.isPrivate,
            followStatus: c.isFollowing ? 'accepted' : (c.isPending ? 'pending' : 'none'),
            isFollowedBy: c.isFollower,
          ),
        )
        .toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return FollowListResult(users: users);
  }

  Future<List<ChatCandidate>> _allChatCandidates() async {
    final auth = AuthService();
    final firstPage = await auth.getChatCandidates();
    if (firstPage.length < _candidatesPageSize) return firstPage;

    // More users than one page: widen coverage with one search per character
    // (usernames only allow a-z, 0-9 and _), merging by id.
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789_';
    final pages = await Future.wait(
      chars.split('').map((ch) => auth.getChatCandidates(query: ch)),
    );
    final byId = <String, ChatCandidate>{for (final c in firstPage) c.id: c};
    for (final page in pages) {
      for (final c in page) {
        byId[c.id] = c;
      }
    }
    return byId.values.toList();
  }
}
