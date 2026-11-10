import 'package:flutter/material.dart';
import '../models/post_item.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../widgets/brote_logo.dart';
import '../widgets/post_card.dart';
import 'follow_requests_screen.dart';

class FeedScreen extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback onOpenProfile;

  const FeedScreen({
    super.key,
    required this.profile,
    required this.onOpenProfile,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PostItem> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    AuthService().postsRefreshNotifier.addListener(_loadPosts);
    _loadPosts();
  }

  @override
  void dispose() {
    AuthService().postsRefreshNotifier.removeListener(_loadPosts);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    final posts = await AuthService().getFeedPosts();
    if (mounted) {
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const BroteLogo(size: 32, useDarkSquircle: true),
            const SizedBox(width: 10),
            Text(
              'brote',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: colorScheme.primary,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<UserProfile?>(
            valueListenable: AuthService().currentUserNotifier,
            builder: (context, user, _) {
              final pending = user?.pendingRequestsCount ?? 0;
              return IconButton(
                tooltip: 'Notificaciones y solicitudes',
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: Icon(Icons.notifications_outlined, color: colorScheme.onSurfaceVariant),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
                  );
                },
              );
            },
          ),
          ValueListenableBuilder<UserProfile?>(
            valueListenable: AuthService().currentUserNotifier,
            builder: (context, user, _) {
              final activeProfile = user ?? widget.profile;
              final avatarUrl = activeProfile.avatarUrl;
              final displayName = activeProfile.displayName;

              return InkWell(
                onTap: widget.onOpenProfile,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: colorScheme.primaryFixedDim,
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? NetworkImage(avatarUrl)
                        : null,
                    onBackgroundImageError: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? (exception, stackTrace) {}
                        : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: colorScheme.onPrimaryFixedVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.6)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: colorScheme.primary,
              indicatorWeight: 3,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(text: 'Para ti'),
                Tab(text: 'Siguiendo'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostsList(colorScheme, textTheme),
          _buildFollowingPostsList(colorScheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildPostsList(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPosts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dynamic_feed_rounded, size: 54, color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'No hay publicaciones aún',
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sé el primero en compartir algo o seguí a más personas para ver sus publicaciones acá.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _posts.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        itemBuilder: (context, index) {
          final post = _posts[index];
          return PostCard(post: post);
        },
      ),
    );
  }

  Widget _buildFollowingPostsList(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentUserId = AuthService().currentUser?.id;
    final followingPosts = _posts.where((p) => p.authorId != currentUserId).toList();

    if (followingPosts.isEmpty) {
      return _buildFollowingEmptyState(colorScheme, textTheme);
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: followingPosts.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        itemBuilder: (context, index) {
          final post = followingPosts[index];
          return PostCard(post: post);
        },
      ),
    );
  }

  Widget _buildFollowingEmptyState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, size: 54, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Aún no seguís a nadie',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Seguí a creadores, amigos y páginas de tu interés en la pestaña Buscar para ver sus publicaciones acá.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
