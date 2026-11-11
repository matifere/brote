import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/app_notification.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';

class NotificationsResult {
  final List<AppNotification> items;

  /// False while the server has no notifications endpoints: then only pending
  /// follow requests and unread chats are shown.
  final bool fromServer;

  const NotificationsResult(this.items, {required this.fromServer});
}

/// Loads notifications and keeps the unread count for the bell badge.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const Duration _serverRetry = Duration(minutes: 5);

  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  DateTime? _serverUnavailableSince;

  /// After a failure, try the server again every few minutes (it may have been deployed meanwhile).
  bool get _shouldTryServer {
    final since = _serverUnavailableSince;
    return since == null || DateTime.now().difference(since) > _serverRetry;
  }

  Future<NotificationsResult> fetch() async {
    if (!AuthService().isAuthenticated) {
      unreadCount.value = 0;
      return const NotificationsResult([], fromServer: true);
    }

    if (_shouldTryServer) {
      final data = await _request('GET', '/api/notifications');
      final list = data?['notifications'];
      if (list is List) {
        _serverUnavailableSince = null;
        final items = list.whereType<Map<String, dynamic>>().map(AppNotification.fromJson).toList();
        unreadCount.value = (data!['unreadCount'] as num?)?.toInt() ?? items.where((n) => !n.isRead).length;
        return NotificationsResult(items, fromServer: true);
      }
      _serverUnavailableSince = DateTime.now();
    }

    final items = await _localNotifications();
    unreadCount.value = items.length;
    return NotificationsResult(items, fromServer: false);
  }

  Future<void> refreshUnreadCount() async {
    if (!AuthService().isAuthenticated) {
      unreadCount.value = 0;
      return;
    }
    if (_shouldTryServer) {
      final data = await _request('GET', '/api/notifications/unread-count');
      final count = data?['unreadCount'];
      if (count is num) {
        _serverUnavailableSince = null;
        unreadCount.value = count.toInt();
        return;
      }
      _serverUnavailableSince = DateTime.now();
    }
    unreadCount.value = (await _localNotifications()).length;
  }

  Future<void> markAllRead() async {
    // Local notifications are pending requests and unread chats: they clear when handled
    if (_serverUnavailableSince != null) return;
    unreadCount.value = 0;
    await _request('POST', '/api/notifications/read');
  }

  /// What the current API can tell without the notifications endpoints.
  Future<List<AppNotification>> _localNotifications() async {
    final (requests, chats) = await (AuthService().getFollowRequests(), AuthService().getConversations()).wait;
    final items = [
      for (final request in requests)
        AppNotification(
          id: 'request-${request.id}',
          kind: NotificationKind.followRequest,
          actor: UserProfile(
            id: request.id,
            username: request.username,
            displayName: request.displayName,
            avatarUrl: request.avatarUrl,
          ),
          createdAt: request.createdAt,
        ),
      for (final chat in chats)
        if (chat.unreadCount > 0 && chat.otherParticipant != null)
          AppNotification(
            id: 'chat-${chat.id}',
            kind: NotificationKind.message,
            actor: chat.otherParticipant!,
            conversationId: chat.id,
            createdAt: chat.lastMessageAt,
          ),
    ];
    final oldest = DateTime.fromMillisecondsSinceEpoch(0);
    items.sort((a, b) => (b.createdAt ?? oldest).compareTo(a.createdAt ?? oldest));
    return items;
  }

  /// Returns the decoded JSON body on success, or null when the request fails
  /// (including servers that don't have the notifications endpoints yet).
  Future<Map<String, dynamic>?> _request(String method, String path) async {
    final token = AuthService().sessionToken;
    if (token == null) return null;
    try {
      final uri = Uri.parse('${AuthService().baseUrl}$path');
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
      final response = method == 'POST'
          ? await http.post(uri, headers: headers).timeout(const Duration(seconds: 10))
          : await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> && data['success'] == true ? data : null;
    } catch (e) {
      debugPrint('Notifications request failed ($method $path): $e');
      return null;
    }
  }
}
