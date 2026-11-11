import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/notifications_screen.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

/// Bell with the unread notifications count; opens the notifications screen.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    // Profile refreshes bring new follow requests; recount then
    AuthService().currentUserNotifier.addListener(_refresh);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    AuthService().currentUserNotifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => NotificationService().refreshUnreadCount();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService().unreadCount,
      builder: (context, count, _) {
        return IconButton(
          tooltip: 'Notificaciones',
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: Icon(Icons.notifications_outlined, color: colorScheme.onSurfaceVariant),
          ),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            _refresh();
          },
        );
      },
    );
  }
}
