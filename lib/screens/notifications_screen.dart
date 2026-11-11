import 'package:flutter/material.dart';
import '../models/app_notification.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'chat_conversation_screen.dart';
import 'follow_requests_screen.dart';
import 'profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _fromServer = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await NotificationService().fetch();
    if (!mounted) return;
    setState(() {
      _items = result.items;
      _fromServer = result.fromServer;
      _isLoading = false;
    });
    // They stay highlighted on this visit, and count as read from now on
    if (result.fromServer && result.items.any((n) => !n.isRead)) {
      await NotificationService().markAllRead();
    }
  }

  Future<void> _open(AppNotification notification) async {
    final Widget screen = switch (notification.kind) {
      NotificationKind.followRequest => const FollowRequestsScreen(),
      NotificationKind.message when notification.conversationId != null => ChatConversationScreen(
          conversationId: notification.conversationId!,
          otherParticipant: notification.actor,
        ),
      // Liked and commented posts are on your own profile
      NotificationKind.like || NotificationKind.comment when AuthService().currentUser != null =>
        ProfileScreen(profile: AuthService().currentUser!),
      _ => ProfileScreen(profile: notification.actor),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!_fromServer) _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text('Notificaciones')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (!_fromServer) _buildLocalModeNotice(colorScheme, textTheme),
                  if (_items.isEmpty)
                    _buildEmptyState(colorScheme, textTheme)
                  else
                    ..._items.map((n) => _buildTile(n, colorScheme, textTheme)),
                ],
              ),
            ),
    );
  }

  Widget _buildLocalModeNotice(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Por ahora ves solicitudes de seguimiento y mensajes sin leer. Los me gusta y los seguidores nuevos '
              'aparecen cuando se actualice el servidor.',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      child: Column(
        children: [
          Icon(Icons.notifications_none_rounded, size: 56, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('No tenés notificaciones', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Cuando alguien te dé me gusta, te siga o te escriba, lo vas a ver acá.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(AppNotification notification, ColorScheme colorScheme, TextTheme textTheme) {
    final actor = notification.actor;
    final avatarUrl = actor.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final (IconData kindIcon, Color kindColor) = switch (notification.kind) {
      NotificationKind.like => (Icons.favorite_rounded, Colors.redAccent),
      NotificationKind.comment => (Icons.mode_comment_rounded, colorScheme.primary),
      NotificationKind.follow || NotificationKind.followAccepted => (Icons.person_add_alt_1_rounded, colorScheme.primary),
      NotificationKind.followRequest => (Icons.group_add_rounded, colorScheme.tertiary),
      NotificationKind.message => (Icons.chat_bubble_rounded, colorScheme.primary),
      NotificationKind.unknown => (Icons.notifications_rounded, colorScheme.outline),
    };
    final details = [
      if (notification.postPreview != null) '"${notification.postPreview}"',
      if (notification.timeAgo.isNotEmpty) notification.timeAgo,
    ].join(' · ');

    return Material(
      color: notification.isRead ? Colors.transparent : colorScheme.primaryContainer.withValues(alpha: 0.18),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              onBackgroundImageError: hasAvatar ? (_, _) {} : null,
              child: hasAvatar
                  ? null
                  : Text(
                      actor.displayName.isNotEmpty ? actor.displayName[0].toUpperCase() : '?',
                      style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                    ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: kindColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 1.5),
                ),
                child: Icon(kindIcon, size: 11, color: Colors.white),
              ),
            ),
          ],
        ),
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: actor.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: ' ${notification.message}'),
            ],
          ),
          style: textTheme.bodyMedium,
        ),
        subtitle: details.isEmpty
            ? null
            : Text(
                details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
        trailing: notification.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
              ),
        onTap: () => _open(notification),
      ),
    );
  }
}
