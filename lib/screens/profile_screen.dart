import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'feed_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<PostItem> _userPosts = [
    PostItem(
      id: 'p1',
      authorName: '', // will populate with widget.profile
      authorUsername: '',
      isVerified: true,
      timeAgo: 'hace 2 días',
      text:
          '🌱 Cosechando los primeros brotes de la temporada. Recordatorio de que todo cambio significativo empieza como una semilla diminuta que recibe cuidado diario.\n\n#Permacultura #BroteVerde',
      imageUrl: 'https://images.unsplash.com/photo-1592417817098-8f3d69102553?auto=format&fit=crop&w=1200&q=80',
      likesCount: 56,
      commentsCount: 9,
      repostsCount: 4,
      isLiked: true,
    ),
    PostItem(
      id: 'p2',
      authorName: '',
      authorUsername: '',
      isVerified: true,
      timeAgo: 'hace 5 días',
      text:
          'Bienvenidos a mi espacio en Brote. Construyamos juntos una red social más humana, orgánica y enfocada en lo que de verdad florece.',
      likesCount: 89,
      commentsCount: 14,
      repostsCount: 11,
      isLiked: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que querés salir de tu cuenta?'),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Cerrar Sesión'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final displayName = widget.profile.displayName;
    final username = widget.profile.username;
    final bio = widget.profile.bio ??
        'Amante de la naturaleza, permacultura y diseño sustentable. Construyendo comunidad en tiempo real.';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              backgroundColor: colorScheme.surface,
              actions: [
                IconButton(
                  tooltip: 'Compartir perfil',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Enlace copiado: brote.app/@$username')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Cerrar sesión',
                  icon: Icon(Icons.logout_rounded, color: colorScheme.error),
                  onPressed: _handleLogout,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Header Banner
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primaryContainer,
                            colorScheme.secondaryContainer,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Opacity(
                        opacity: 0.12,
                        child: Icon(Icons.eco_rounded, size: 240, color: colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar and Edit Button Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -32),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.surface, width: 4),
                            ),
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: colorScheme.primary,
                              child: Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              OutlinedButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Editor de perfil próximamente.')),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: const Text('Editar perfil'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // User Identity
                    Text(
                      displayName,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),

                    // Bio
                    Text(
                      bio,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Metrics Row (Publicaciones, Seguidores, Siguiendo)
                    Row(
                      children: [
                        _buildMetric('142', 'Publicaciones', textTheme, colorScheme),
                        const SizedBox(width: 20),
                        _buildMetric('4.8k', 'Seguidores', textTheme, colorScheme),
                        const SizedBox(width: 20),
                        _buildMetric('620', 'Siguiendo', textTheme, colorScheme),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: colorScheme.primary,
                  indicatorWeight: 3,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Publicaciones'),
                    Tab(text: 'Respuestas'),
                    Tab(text: 'Multimedia'),
                    Tab(text: 'Me gusta'),
                  ],
                ),
                colorScheme.surface,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPostsStream(colorScheme, textTheme),
            _buildEmptyTab('Aún no hay respuestas publicadas.', colorScheme, textTheme),
            _buildEmptyTab('Aún no hay fotos ni videos subidos.', colorScheme, textTheme),
            _buildEmptyTab('Aún no diste "me gusta" a publicaciones.', colorScheme, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String number, String label, TextTheme textTheme, ColorScheme colorScheme) {
    return Row(
      children: [
        Text(
          number,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildPostsStream(ColorScheme colorScheme, TextTheme textTheme) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _userPosts.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (context, index) {
        final post = _userPosts[index];
        final authorName = widget.profile.displayName;
        final authorUsername = widget.profile.username;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          authorName,
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded, size: 14, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '@$authorUsername',
                          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '· ${post.timeAgo}',
                          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      post.text,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                    if (post.imageUrl != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          post.imageUrl!,
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const SizedBox(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 17, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text('${post.commentsCount}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.repeat_rounded, size: 17, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text('${post.repostsCount}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(
                              post.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 17,
                              color: post.isLiked
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text('${post.likesCount}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        Icon(Icons.bookmark_border_rounded,
                            size: 17, color: colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyTab(String message, ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color _bgColor;

  _SliverAppBarDelegate(this._tabBar, this._bgColor);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: _bgColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
