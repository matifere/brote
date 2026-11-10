import 'package:flutter/material.dart';
import '../models/user_profile.dart';

class PostItem {
  final String id;
  final String authorName;
  final String authorUsername;
  final String? authorAvatarUrl;
  final bool isVerified;
  final String timeAgo;
  final String text;
  final String? imageUrl;
  int likesCount;
  int commentsCount;
  int repostsCount;
  bool isLiked;
  bool isBookmarked;

  PostItem({
    required this.id,
    required this.authorName,
    required this.authorUsername,
    this.authorAvatarUrl,
    this.isVerified = false,
    required this.timeAgo,
    required this.text,
    this.imageUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.repostsCount = 0,
    this.isLiked = false,
    this.isBookmarked = false,
  });
}

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
  final TextEditingController _composerController = TextEditingController();

  final List<PostItem> _posts = [
    PostItem(
      id: '1',
      authorName: 'Elena Rostova',
      authorUsername: 'elena_dev',
      isVerified: true,
      timeAgo: '22m',
      text:
          '🌱 Acabamos de implementar los nuevos principios de permacultura en la terraza comunitaria. El sistema de riego solar ya está funcionando al 100%. ¡Los primeros brotes de albahaca y tomates cherry se ven radiantes!\n\n#HuertaUrbana #Sostenibilidad #Permacultura',
      imageUrl: 'https://images.unsplash.com/photo-1530836369250-ef72a3f5cda8?auto=format&fit=crop&w=1200&q=80',
      likesCount: 84,
      commentsCount: 16,
      repostsCount: 12,
      isLiked: true,
    ),
    PostItem(
      id: '2',
      authorName: 'Martín Morales',
      authorUsername: 'morales_builds',
      isVerified: true,
      timeAgo: '1h',
      text:
          'Intercambio de semillas nativas este sábado en el parque central 🌿 Traigan sus variedades criollas para diversificar nuestros cultivos. La biodiversidad es resistencia colectiva.\n\n¿Quiénes se suman?',
      likesCount: 132,
      commentsCount: 42,
      repostsCount: 29,
    ),
    PostItem(
      id: '3',
      authorName: 'Camila Varela',
      authorUsername: 'camilav',
      isVerified: false,
      timeAgo: '3h',
      text:
          'Diseñando las fichas botánicas para identificar polinizadores en espacios urbanos 🐝 Abejas nativas, abejorros y mariposas son los verdaderos arquitectos de nuestros ecosistemas.',
      imageUrl: 'https://images.unsplash.com/photo-1587334274328-64186a80aeee?auto=format&fit=crop&w=1200&q=80',
      likesCount: 215,
      commentsCount: 38,
      repostsCount: 45,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _showNewPostModal() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Compartir un brote',
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      widget.profile.displayName.isNotEmpty
                          ? widget.profile.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _composerController,
                      maxLines: 4,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '¿Qué semilla o idea querés sembrar hoy?...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Agregar foto',
                        icon: Icon(Icons.image_outlined, color: colorScheme.primary),
                        onPressed: () {},
                      ),
                      IconButton(
                        tooltip: 'Etiqueta o tema',
                        icon: Icon(Icons.tag_rounded, color: colorScheme.primary),
                        onPressed: () {},
                      ),
                      IconButton(
                        tooltip: 'Ubicación',
                        icon: Icon(Icons.location_on_outlined, color: colorScheme.primary),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.eco_rounded, size: 18),
                    label: const Text('Brotar'),
                    onPressed: () {
                      final text = _composerController.text.trim();
                      if (text.isNotEmpty) {
                        setState(() {
                          _posts.insert(
                            0,
                            PostItem(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              authorName: widget.profile.displayName,
                              authorUsername: widget.profile.username,
                              timeAgo: 'ahora',
                              text: text,
                              likesCount: 0,
                              commentsCount: 0,
                              repostsCount: 0,
                            ),
                          );
                        });
                        _composerController.clear();
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.eco_rounded, color: colorScheme.onPrimaryContainer, size: 20),
            ),
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
          IconButton(
            tooltip: 'Notificaciones',
            icon: Icon(Icons.notifications_outlined, color: colorScheme.onSurfaceVariant),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No hay notificaciones nuevas.')),
              );
            },
          ),
          InkWell(
            onTap: widget.onOpenProfile,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: colorScheme.primaryFixedDim,
                child: Text(
                  widget.profile.displayName.isNotEmpty
                      ? widget.profile.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: colorScheme.onPrimaryFixedVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        tooltip: 'Crear publicación',
        onPressed: _showNewPostModal,
        child: const Icon(Icons.edit_note_rounded, size: 26),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostsList(colorScheme, textTheme),
          _buildFollowingEmptyState(colorScheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildPostsList(ColorScheme colorScheme, TextTheme textTheme) {
    return ListView.separated(
      itemCount: _posts.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _buildPostCard(post, colorScheme, textTheme);
      },
    );
  }

  Widget _buildPostCard(PostItem post, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Text(
              post.authorName.isNotEmpty ? post.authorName[0].toUpperCase() : '?',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Name, Verified badge, Username, Time)
                Row(
                  children: [
                    Text(
                      post.authorName,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (post.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified_rounded, size: 15, color: colorScheme.primary),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      '@${post.authorUsername}',
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

                // Post Content Text
                Text(
                  post.text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    height: 1.45,
                  ),
                ),

                // Optional Image
                if (post.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      post.imageUrl!,
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(Icons.image_not_supported_outlined, color: colorScheme.outline),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Post Actions Bar (Comments, Reposts, Likes, Bookmark)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Comments
                    _buildActionButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: post.commentsCount > 0 ? '${post.commentsCount}' : '',
                      color: colorScheme.onSurfaceVariant,
                      onTap: () {},
                    ),
                    // Repost
                    _buildActionButton(
                      icon: Icons.repeat_rounded,
                      label: post.repostsCount > 0 ? '${post.repostsCount}' : '',
                      color: colorScheme.onSurfaceVariant,
                      onTap: () {
                        setState(() => post.repostsCount++);
                      },
                    ),
                    // Like
                    _buildActionButton(
                      icon: post.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      label: post.likesCount > 0 ? '${post.likesCount}' : '',
                      color: post.isLiked ? colorScheme.tertiaryContainer : colorScheme.onSurfaceVariant,
                      onTap: () {
                        setState(() {
                          post.isLiked = !post.isLiked;
                          post.likesCount += post.isLiked ? 1 : -1;
                        });
                      },
                    ),
                    // Bookmark
                    _buildActionButton(
                      icon: post.isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      label: '',
                      color: post.isBookmarked ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      onTap: () {
                        setState(() => post.isBookmarked = !post.isBookmarked);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
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
              'Explorá la pestaña Buscar para descubrir comunidades, huertas y proyectos afines.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
