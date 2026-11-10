import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../widgets/brote_logo.dart';
import 'auth_screen.dart';
import 'edit_profile_screen.dart';
import 'feed_screen.dart';
import 'follow_requests_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfile _currentProfile;

  bool get _isOwnProfile =>
      AuthService().currentUser == null ||
      AuthService().currentUser?.id == _currentProfile.id;

  bool get _isContentLocked =>
      !_isOwnProfile && _currentProfile.isPrivate && !_currentProfile.isFollowing;

  bool _isFollowLoading = false;

  Future<void> _handleFollowToggle() async {
    setState(() => _isFollowLoading = true);
    if (_currentProfile.isFollowing || _currentProfile.isPending) {
      final updated = await AuthService().unfollowUser(_currentProfile.id);
      if (mounted && updated != null) {
        setState(() => _currentProfile = updated);
      }
    } else {
      final updated = await AuthService().followUser(_currentProfile.id);
      if (mounted && updated != null) {
        setState(() => _currentProfile = updated);
      }
    }
    if (mounted) {
      setState(() => _isFollowLoading = false);
    }
  }

  final List<PostItem> _userPosts = [
    PostItem(
      id: 'p1',
      authorName: '', // will populate with widget.profile
      authorUsername: '',
      isVerified: true,
      timeAgo: 'hace 2 días',
      text:
          'Probando la cámara nueva por el centro de la ciudad. El rango dinámico que tiene es una locura total 📸🔥 Dejen sus opiniones en los comentarios.\n\n#Fotografia #Urbano #Estilo #Street',
      imageUrl: 'https://images.unsplash.com/photo-1514565131-fce0801e5785?auto=format&fit=crop&w=1200&q=80',
      likesCount: 342,
      commentsCount: 28,
      repostsCount: 14,
      isLiked: true,
    ),
    PostItem(
      id: 'p2',
      authorName: '',
      authorUsername: '',
      isVerified: true,
      timeAgo: 'hace 5 días',
      text:
          '¡Bienvenidos a mi perfil en Brote! Síganme para ver más fotos, proyectos y contenido todos los días ✌️ Les dejo un abrazo enorme.',
      likesCount: 512,
      commentsCount: 46,
      repostsCount: 22,
      isLiked: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final isMe = AuthService().currentUser?.id == widget.profile.id;
    _currentProfile = isMe ? (AuthService().currentUser ?? widget.profile) : widget.profile;
    if (isMe) {
      AuthService().currentUserNotifier.addListener(_onProfileChanged);
      AuthService().fetchMyProfile();
    } else {
      AuthService().fetchUserProfile(widget.profile.username).then((fresh) {
        if (fresh != null && mounted) {
          setState(() => _currentProfile = fresh);
        }
      });
    }
  }

  @override
  void dispose() {
    AuthService().currentUserNotifier.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted && AuthService().currentUser != null) {
      setState(() {
        _currentProfile = AuthService().currentUser!;
      });
    }
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: _currentProfile),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _currentProfile = updated;
      });
    }
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

    final displayName = _currentProfile.displayName;
    final username = _currentProfile.username;
    final bio = _currentProfile.bio ??
        'Creador de contenido & fotografía. Apasionado por la tecnología, la música y el diseño. Conectando todos los días.';
    final avatarUrl = _currentProfile.avatarUrl;
    final bannerUrl = _currentProfile.bannerUrl;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: false,
              floating: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: colorScheme.surface,
              leading: Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
              title: Row(
                children: [
                  const BroteLogo(size: 28, useDarkSquircle: true),
                  const SizedBox(width: 8),
                  Text(
                    'brote',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
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
                if (_isOwnProfile && (_currentProfile.isPrivate || _currentProfile.pendingRequestsCount > 0))
                  IconButton(
                    tooltip: 'Solicitudes de seguimiento',
                    icon: Badge(
                      isLabelVisible: _currentProfile.pendingRequestsCount > 0,
                      label: Text('${_currentProfile.pendingRequestsCount}'),
                      child: const Icon(Icons.group_add_outlined),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
                      );
                      AuthService().fetchMyProfile();
                    },
                  ),
                if (_isOwnProfile)
                  IconButton(
                    tooltip: 'Cerrar sesión',
                    icon: Icon(Icons.logout_rounded, color: colorScheme.error),
                    onPressed: _handleLogout,
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover Banner with Avatar overlapping
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Modern Cover Banner with Dark Gradient / Studio aesthetic
                      Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF1E2230),
                              colorScheme.primary.withValues(alpha: 0.15),
                              const Color(0xFF12131A),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: (bannerUrl != null && bannerUrl.isNotEmpty)
                            ? Image.network(
                                bannerUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const SizedBox(),
                              )
                            : Image.network(
                                'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&q=80',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const SizedBox(),
                              ),
                      ),
                      // Gradient overlay to blend smoothly into surface
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.55),
                                colorScheme.surface,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.7, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Avatar positioned overlapping the bottom of the banner
                      Positioned(
                        left: 16,
                        bottom: -36,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: colorScheme.surface, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: colorScheme.primary,
                            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                ? NetworkImage(avatarUrl)
                                : null,
                            onBackgroundImageError: (avatarUrl != null && avatarUrl.isNotEmpty)
                                ? (exception, stackTrace) {}
                                : null,
                            child: (avatarUrl == null || avatarUrl.isEmpty)
                                ? Text(
                                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Actions row below banner (Edit Profile on right) + Identity
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isOwnProfile)
                              OutlinedButton(
                                onPressed: _openEditProfile,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                  side: BorderSide(color: colorScheme.outlineVariant),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: Text(
                                  'Editar perfil',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              )
                            else
                              FilledButton(
                                onPressed: _isFollowLoading ? null : _handleFollowToggle,
                                style: FilledButton.styleFrom(
                                  backgroundColor: (_currentProfile.isFollowing || _currentProfile.isPending)
                                      ? colorScheme.surfaceContainerHighest
                                      : colorScheme.primary,
                                  foregroundColor: (_currentProfile.isFollowing || _currentProfile.isPending)
                                      ? colorScheme.onSurface
                                      : colorScheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: _isFollowLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(
                                        _currentProfile.isFollowing
                                            ? 'Siguiendo'
                                            : _currentProfile.isPending
                                                ? 'Solicitado'
                                                : 'Seguir',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // User Identity
                        Row(
                          children: [
                            Text(
                              displayName,
                              style: textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (_currentProfile.isPrivate)
                              Tooltip(
                                message: 'Cuenta privada',
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.lock_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            else
                              Icon(Icons.verified, size: 20, color: colorScheme.primary),
                          ],
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
                        _buildMetric('${_userPosts.length}', 'Publicaciones', textTheme, colorScheme),
                        const SizedBox(width: 20),
                        _buildMetric('${_currentProfile.followersCount}', 'Seguidores', textTheme, colorScheme),
                        const SizedBox(width: 20),
                        _buildMetric('${_currentProfile.followingCount}', 'Siguiendo', textTheme, colorScheme),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Follow Requests Banner if private or has pending requests
                    if (_isOwnProfile && (_currentProfile.isPrivate || _currentProfile.pendingRequestsCount > 0)) ...[
                      _buildFollowRequestsBanner(colorScheme, textTheme),
                      const SizedBox(height: 16),
                    ],

                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
          ];
        },
        body: _isContentLocked
            ? _buildPrivateAccountNotice(colorScheme, textTheme)
            : _buildPostsStream(colorScheme, textTheme),
      ),
    );
  }

  Widget _buildPrivateAccountNotice(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline_rounded, size: 48, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Esta cuenta es privada',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Seguí a esta cuenta para ver sus fotos y publicaciones.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
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
    if (_userPosts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notes_rounded, size: 48, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                'Aún no hay publicaciones',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Las publicaciones que comparta este perfil aparecerán acá.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _userPosts.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (context, index) {
        final post = _userPosts[index];
        final authorName = _currentProfile.displayName;
        final authorUsername = _currentProfile.username;
        final authorAvatar = _currentProfile.avatarUrl;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: (authorAvatar != null && authorAvatar.isNotEmpty)
                    ? NetworkImage(authorAvatar)
                    : null,
                onBackgroundImageError: (authorAvatar != null && authorAvatar.isNotEmpty)
                    ? (exception, stackTrace) {}
                    : null,
                child: (authorAvatar == null || authorAvatar.isEmpty)
                    ? Text(
                        authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
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

  Widget _buildFollowRequestsBanner(ColorScheme colorScheme, TextTheme textTheme) {
    final count = _currentProfile.pendingRequestsCount;
    final hasRequests = count > 0;

    return Material(
      color: hasRequests
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasRequests
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
          );
          AuthService().fetchMyProfile();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasRequests ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.group_add_rounded,
                  size: 20,
                  color: hasRequests ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
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
                          'Solicitudes de seguimiento',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (hasRequests) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasRequests
                          ? '$count ${count == 1 ? "persona quiere" : "personas quieren"} seguirte'
                          : 'Revisá las solicitudes pendientes de tu cuenta',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
