import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import 'profile_screen.dart';

/// Shows who follows [profile] (tab 0) and who [profile] follows (tab 1).
class FollowListScreen extends StatefulWidget {
  final UserProfile profile;
  final int initialTab;

  const FollowListScreen({
    super.key,
    required this.profile,
    this.initialTab = 0,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  FollowListResult? _followers;
  FollowListResult? _following;

  bool get _isOwnProfile => AuthService().currentUser?.id == widget.profile.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _load(FollowListType.followers),
      _load(FollowListType.following),
    ]);
  }

  Future<void> _load(FollowListType type) async {
    final result = await FollowService().fetch(widget.profile, type);
    if (!mounted) return;
    setState(() {
      if (type == FollowListType.followers) {
        _followers = result;
      } else {
        _following = result;
      }
    });
  }

  void _openProfile(UserProfile user) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(profile: user)),
    );
    // Following/unfollowing from that profile changes these lists.
    if (mounted) _loadAll();
  }

  String _tabLabel(String label, FollowListResult? result, int fallbackCount) {
    final count = (result != null && !result.locked && !result.unavailable)
        ? result.users.length
        : fallbackCount;
    return '$count $label';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile.displayName,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '@${widget.profile.username}',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: _tabLabel('Seguidores', _followers, widget.profile.followersCount)),
            Tab(text: _tabLabel('Siguiendo', _following, widget.profile.followingCount)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(FollowListType.followers, _followers, colorScheme, textTheme),
          _buildList(FollowListType.following, _following, colorScheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildList(
    FollowListType type,
    FollowListResult? result,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    if (result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isFollowers = type == FollowListType.followers;

    if (result.locked) {
      return _buildMessage(
        icon: Icons.lock_rounded,
        title: 'Esta cuenta es privada',
        body: 'Seguí a @${widget.profile.username} para ver sus seguidores y a quién sigue.',
        colorScheme: colorScheme,
        textTheme: textTheme,
        onRefresh: () => _load(type),
      );
    }

    if (result.unavailable) {
      return _buildMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Todavía no disponible',
        body: 'Por ahora solo podés ver tus propios seguidores y seguidos. '
            'Ver los de otras cuentas requiere una actualización del servidor.',
        colorScheme: colorScheme,
        textTheme: textTheme,
        onRefresh: () => _load(type),
      );
    }

    if (result.users.isEmpty) {
      final who = _isOwnProfile ? null : '@${widget.profile.username}';
      return _buildMessage(
        icon: isFollowers ? Icons.people_outline_rounded : Icons.person_add_alt_rounded,
        title: isFollowers
            ? (who == null ? 'Todavía no tenés seguidores' : '$who no tiene seguidores')
            : (who == null ? 'Todavía no seguís a nadie' : '$who no sigue a nadie'),
        body: isFollowers
            ? 'Cuando alguien siga esta cuenta, va a aparecer acá.'
            : 'Las cuentas seguidas van a aparecer acá.',
        colorScheme: colorScheme,
        textTheme: textTheme,
        onRefresh: () => _load(type),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(type),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: result.users.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          indent: 72,
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
        itemBuilder: (context, index) {
          final user = result.users[index];
          return _buildUserTile(user, isFollowers, colorScheme, textTheme);
        },
      ),
    );
  }

  Widget _buildUserTile(
    UserProfile user,
    bool isFollowersList,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final avatarUrl = user.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final displayName = user.displayName;

    // On your own lists, show the relationship in the other direction.
    String? relation;
    if (_isOwnProfile) {
      if (isFollowersList) {
        relation = user.isFollowing
            ? 'Se siguen mutuamente'
            : (user.isPending ? 'Solicitud enviada' : null);
      } else if (user.isFollowedBy) {
        relation = 'Te sigue';
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
        onBackgroundImageError: hasAvatar ? (_, _) {} : null,
        child: !hasAvatar
            ? Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.isVerified) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified_rounded, size: 14, color: colorScheme.primary),
          ],
          if (user.isPrivate) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock_rounded, size: 12, color: colorScheme.onSurfaceVariant),
          ],
        ],
      ),
      subtitle: Text(
        relation == null ? '@${user.username}' : '@${user.username} · $relation',
        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
      onTap: () => _openProfile(user),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String body,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(icon, size: 54, color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
