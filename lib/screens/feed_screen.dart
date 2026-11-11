import 'package:flutter/material.dart';
import '../models/post_item.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../widgets/brote_logo.dart';
import '../widgets/notification_bell.dart';
import '../widgets/post_card.dart';

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
  List<PostItem> _forYouPosts = [];
  List<PostItem> _followingPosts = [];
  List<PostItem> _reviewPosts = [];
  bool _isLoadingForYou = true;
  bool _isLoadingFollowing = true;
  bool _isLoadingReviews = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    await Future.wait([
      _loadForYou(),
      _loadFollowing(),
      _loadReviews(),
    ]);
  }

  Future<void> _loadReviews() async {
    final posts = await AuthService().getFeedPosts(filter: 'reviews');
    if (mounted) {
      setState(() {
        // Servers without the reviews filter return the whole feed
        _reviewPosts = posts.where((p) => p.parsedContent.review != null).toList();
        _isLoadingReviews = false;
      });
    }
  }

  /// Reviews from every tab, newest first.
  List<PostItem> get _allReviews {
    final byId = <String, PostItem>{};
    for (final post in [..._reviewPosts, ..._forYouPosts, ..._followingPosts]) {
      if (post.parsedContent.review != null) byId.putIfAbsent(post.id, () => post);
    }
    final oldest = DateTime.fromMillisecondsSinceEpoch(0);
    return byId.values.toList()..sort((a, b) => (b.createdAt ?? oldest).compareTo(a.createdAt ?? oldest));
  }

  Future<void> _loadForYou() async {
    final posts = await AuthService().getFeedPosts();
    if (mounted) {
      setState(() {
        _forYouPosts = posts;
        _isLoadingForYou = false;
      });
    }
  }

  Future<void> _loadFollowing() async {
    final posts = await AuthService().getFeedPosts(filter: 'following');
    if (mounted) {
      setState(() {
        _followingPosts = posts;
        _isLoadingFollowing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 16,
        title: isDesktop
            ? Text(
                'Inicio',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              )
            : Row(
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
          const NotificationBell(),
          if (!isDesktop)
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
                Tab(text: 'Reseñas'),
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
          _buildReviewsList(colorScheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildPostsList(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoadingForYou && _forYouPosts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_forYouPosts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadForYou,
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
      onRefresh: _loadForYou,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _forYouPosts.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        itemBuilder: (context, index) {
          final post = _forYouPosts[index];
          return PostCard(post: post);
        },
      ),
    );
  }

  Widget _buildFollowingPostsList(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoadingFollowing && _followingPosts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_followingPosts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFollowing,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            _buildFollowingEmptyState(colorScheme, textTheme),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFollowing,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _followingPosts.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        itemBuilder: (context, index) {
          final post = _followingPosts[index];
          return PostCard(post: post);
        },
      ),
    );
  }

  Widget _buildReviewsList(ColorScheme colorScheme, TextTheme textTheme) {
    final reviews = _allReviews;
    if (_isLoadingReviews && reviews.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (reviews.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPosts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.rate_review_outlined, size: 54, color: colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Todavía no hay reseñas',
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Calificá una película o un tema desde Buscar o Publicar y sumá tu opinión: aparece acá.',
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

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: reviews.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        itemBuilder: (context, index) => PostCard(post: reviews[index]),
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
              'Nada de las cuentas que seguís',
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
