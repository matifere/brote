import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/rating.dart';
import '../models/post_item.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import '../services/theme_service.dart';
import '../widgets/brote_logo.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/rating_stars.dart';
import '../widgets/post_card.dart';
import '../widgets/report_dialog.dart';
import '../widgets/taste_affinity.dart';
import 'admin_moderation_screen.dart';
import 'auth_screen.dart';
import 'chat_conversation_screen.dart';
import 'edit_profile_screen.dart';
import 'follow_list_screen.dart';
import 'follow_requests_screen.dart';
import 'rating_search_screen.dart';

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
  final Set<RatingCategory> _expandedCategories = {};
  List<PostItem> _userPosts = [];
  bool _isLoadingPosts = true;

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

  Future<void> _openChatWithUser() async {
    final res = await AuthService().startConversationWithUser(_currentProfile.id);
    if (!mounted) return;

    if (res['success'] == true && res['conversationId'] != null) {
      final convId = res['conversationId'] as String;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatConversationScreen(
            conversationId: convId,
            otherParticipant: _currentProfile,
          ),
        ),
      );
    } else {
      final error = res['error'] as String? ?? 'No se pudo abrir el chat';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _fetchUserPosts() async {
    final posts = await AuthService().getUserPosts(_currentProfile.username);
    if (mounted) {
      setState(() {
        _userPosts = posts;
        _isLoadingPosts = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final isMe = AuthService().currentUser?.id == widget.profile.id;
    _currentProfile = isMe ? (AuthService().currentUser ?? widget.profile) : widget.profile;
    AuthService().postsRefreshNotifier.addListener(_fetchUserPosts);
    _fetchUserPosts();
    _preloadRatingPosters();

    if (isMe) {
      AuthService().currentUserNotifier.addListener(_onProfileChanged);
      AuthService().fetchMyProfile();
    } else {
      AuthService().fetchUserProfile(widget.profile.username).then((fresh) {
        if (fresh != null && mounted) {
          setState(() => _currentProfile = fresh);
          _preloadRatingPosters();
        }
      });
    }
  }

  void _preloadRatingPosters() {
    final bio = ProfileBio.parse(_currentProfile.bio);
    for (final r in bio.of(RatingCategory.movie)) {
      if (CatalogService().getCachedPoster(r.title, year: r.year) == null) {
        CatalogService().getMoviePoster(r.title, year: r.year).then((url) {
          if (mounted && url != null) {
            setState(() {});
          }
        });
      }
    }
  }

  @override
  void dispose() {
    AuthService().postsRefreshNotifier.removeListener(_fetchUserPosts);
    AuthService().currentUserNotifier.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted && AuthService().currentUser != null) {
      setState(() {
        _currentProfile = AuthService().currentUser!;
      });
      _preloadRatingPosters();
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
      _preloadRatingPosters();
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

  Future<void> _handleBlockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Bloquear a @${_currentProfile.username}?'),
        content: const Text(
          'Dejarás de ver sus publicaciones, comentarios y no podrán interactuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final ok = await AuthService().blockUser(_currentProfile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Usuario bloqueado.' : 'Error al bloquear usuario.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (ok) {
        setState(() {
          _currentProfile = _currentProfile.copyWith(
            isBlocked: true,
            canViewContent: false,
          );
        });
      }
    }
  }

  Future<void> _handleUnblockUser() async {
    final ok = await AuthService().unblockUser(_currentProfile.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Usuario desbloqueado.' : 'Error al desbloquear usuario.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) {
      setState(() {
        _currentProfile = _currentProfile.copyWith(
          isBlocked: false,
          canViewContent: true,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final displayName = _currentProfile.displayName;
    final username = _currentProfile.username;
    final parsedBio = ProfileBio.parse(_currentProfile.bio);
    final bio = parsedBio.text.trim();
    final affinity = _isOwnProfile ? null : _tasteAffinity(parsedBio);
    final avatarUrl = _currentProfile.avatarUrl;
    final bannerUrl = _currentProfile.bannerUrl;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          decoration: isDesktop
              ? BoxDecoration(
                  color: colorScheme.surface,
                  border: Border.symmetric(
                    vertical: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                )
              : null,
          child: NestedScrollView(
            headerSliverBuilder: (_, innerBoxIsScrolled) {
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
                  // Own profile can have up to five actions; let the name give way on narrow phones
                  Flexible(
                    child: Text(
                      'brote',
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                if (_isOwnProfile && (_currentProfile.isAdmin || (AuthService().currentUser?.isAdmin ?? false)))
                  IconButton(
                    tooltip: 'Panel de Moderación',
                    icon: Icon(Icons.shield_outlined, color: colorScheme.primary),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AdminModerationScreen()),
                      );
                    },
                  ),
                IconButton(
                  tooltip: 'Compartir perfil',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => _shareProfile(displayName, username),
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
                    tooltip: 'Apariencia',
                    icon: ValueListenableBuilder<ThemeMode>(
                      valueListenable: ThemeService().mode,
                      builder: (context, mode, _) => Icon(switch (mode) {
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                        ThemeMode.system => Icons.brightness_auto_outlined,
                      }),
                    ),
                    onPressed: _showAppearanceSheet,
                  ),
                if (_isOwnProfile)
                  IconButton(
                    tooltip: 'Cerrar sesión',
                    icon: Icon(Icons.logout_rounded, color: colorScheme.error),
                    onPressed: _handleLogout,
                  ),
                if (!_isOwnProfile)
                  PopupMenuButton<String>(
                    tooltip: 'Más opciones',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (val) {
                      if (val == 'report') {
                        showReportContentDialog(
                          context,
                          userId: _currentProfile.id,
                          targetTitle: 'usuario',
                        );
                      } else if (val == 'block') {
                        _handleBlockUser();
                      } else if (val == 'unblock') {
                        _handleUnblockUser();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Reportar usuario'),
                          ],
                        ),
                      ),
                      if (_currentProfile.isBlocked)
                        const PopupMenuItem(
                          value: 'unblock',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Desbloquear usuario'),
                            ],
                          ),
                        )
                      else
                        PopupMenuItem(
                          value: 'block',
                          child: Row(
                            children: [
                              const Icon(Icons.block_rounded, size: 18, color: Colors.redAccent),
                              const SizedBox(width: 8),
                              Text(
                                'Bloquear a @${_currentProfile.username}',
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ],
                          ),
                        ),
                    ],
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
                            else ...[
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
                              if (!_currentProfile.isPrivate || _currentProfile.isFollowing || _currentProfile.isFollowedBy) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: _openChatWithUser,
                                  icon: const Icon(Icons.mail_outline_rounded, size: 16),
                                  label: const Text('Mensaje'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    side: BorderSide(color: colorScheme.outlineVariant),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                ),
                              ],
                            ],
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
                            else if (_currentProfile.isVerified)
                              Tooltip(
                                message: 'Cuenta verificada',
                                child: Icon(Icons.verified, size: 20, color: colorScheme.primary),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    const SizedBox(height: 12),

                    // Bio
                    if (bio.isNotEmpty) ...[
                      Text(
                        bio,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (_isOwnProfile) ...[
                      InkWell(
                        onTap: _openEditProfile,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_note_rounded, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Agregá una descripción',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Rated movies and music (stored in the bio)
                    for (final category in RatingCategory.values)
                      if (parsedBio.of(category).isNotEmpty || _isOwnProfile) ...[
                        _buildRatingsSection(category, parsedBio.of(category), colorScheme, textTheme),
                        const SizedBox(height: 16),
                      ],

                    if (affinity != null) ...[
                      TasteAffinityCard(affinity: affinity, otherUsername: username),
                      const SizedBox(height: 16),
                    ],

                    // Metrics (Publicaciones, Seguidores, Siguiendo); wraps on narrow phones
                    Wrap(
                      spacing: 20,
                      runSpacing: 4,
                      children: [
                        _buildMetric('${_userPosts.length}', 'Publicaciones', textTheme, colorScheme),
                        _buildMetric('${_currentProfile.followersCount}', 'Seguidores', textTheme, colorScheme,
                            onTap: _isContentLocked ? null : () => _openFollowList(0)),
                        _buildMetric('${_currentProfile.followingCount}', 'Siguiendo', textTheme, colorScheme,
                            onTap: _isContentLocked ? null : () => _openFollowList(1)),
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
        ),
      ),
    );
  }

  /// Ratings both you and this profile have in their bios.
  TasteAffinity? _tasteAffinity(ProfileBio theirs) {
    final me = AuthService().currentUser;
    if (me == null) return null;
    return TasteAffinity.compare(ProfileBio.parse(me.bio), theirs);
  }

  void _shareProfile(String displayName, String username) {
    // brote has no public web address yet, so share the username to search for
    Clipboard.setData(ClipboardData(text: 'Seguí a $displayName (@$username) en brote'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiaste @$username: pegalo donde quieras compartirlo')),
    );
  }

  Future<void> _showAppearanceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (sheetContext) => SafeArea(
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService().mode,
          builder: (context, mode, _) => RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (value) {
              if (value != null) ThemeService().setMode(value);
              Navigator.of(sheetContext).pop();
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Apariencia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  secondary: Icon(Icons.brightness_auto_outlined),
                  title: Text('Igual que el dispositivo'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  secondary: Icon(Icons.light_mode_outlined),
                  title: Text('Claro'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  secondary: Icon(Icons.dark_mode_outlined),
                  title: Text('Oscuro'),
                ),
                SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRatingSearch(RatingCategory category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RatingSearchScreen(category: category)),
    );
    if (!mounted) return;
    final updated = AuthService().currentUser;
    if (updated != null && updated.id == _currentProfile.id) {
      setState(() => _currentProfile = updated);
      _preloadRatingPosters();
    }
  }

  Widget _buildRatingsSection(RatingCategory category, List<RatedItem> ratings, ColorScheme colorScheme, TextTheme textTheme) {
    final isMovie = category == RatingCategory.movie;
    final isExpanded = _expandedCategories.contains(category);
    final canExpand = ratings.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(isMovie ? Icons.local_movies_outlined : Icons.library_music_outlined, size: 18, color: colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isMovie ? 'Películas' : 'Música',
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (ratings.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${ratings.length}',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (canExpand)
              TextButton.icon(
                onPressed: () => setState(() {
                  if (isExpanded) {
                    _expandedCategories.remove(category);
                  } else {
                    _expandedCategories.add(category);
                  }
                }),
                icon: Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                label: Text(
                  isExpanded ? 'Comprimir' : 'Expandir',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            if (_isOwnProfile) ...[
              if (canExpand) const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _openRatingSearch(category),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Calificar'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (ratings.isEmpty)
          Text(
            isMovie
                ? 'Buscá películas, calificalas y aparecen acá en tu descripción.'
                : 'Buscá temas o álbumes, calificalos y aparecen acá en tu descripción.',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          )
        else if (isExpanded)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rating in ratings)
                _buildRatingChip(rating, colorScheme, textTheme),
              if (canExpand)
                _buildExpandChip(
                  category: category,
                  isExpanded: true,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
            ],
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (var i = 0; i < ratings.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _buildRatingChip(ratings[i], colorScheme, textTheme),
                ],
                if (canExpand) ...[
                  const SizedBox(width: 8),
                  _buildExpandChip(
                    category: category,
                    isExpanded: false,
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildExpandChip({
    required RatingCategory category,
    required bool isExpanded,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return InkWell(
      onTap: () => setState(() {
        if (isExpanded) {
          _expandedCategories.remove(category);
        } else {
          _expandedCategories.add(category);
        }
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.unfold_more_rounded,
              size: 15,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              isExpanded ? 'Comprimir' : 'Ver todas',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingChip(RatedItem rating, ColorScheme colorScheme, TextTheme textTheme) {
    final detail = rating.detail;
    final isMovie = rating.category == RatingCategory.movie;
    final posterUrl = isMovie
        ? CatalogService().getCachedPoster(rating.title, year: rating.year)
        : null;

    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: isMovie && posterUrl != null ? 8 : 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (posterUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                posterUrl,
                width: 20,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: rating.title,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (detail != null)
                  TextSpan(
                    text: isMovie ? ' $detail' : ' · $detail',
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                const WidgetSpan(child: SizedBox(width: 6)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: RatingStars(stars: rating.stars, size: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (posterUrl != null) {
      return GestureDetector(
        onTap: () => openFullScreenImage(
          context,
          imageUrl: posterUrl,
          heroTag: 'profile-rating-${rating.title}-${rating.year}',
          title: rating.title,
          subtitle: rating.detail,
        ),
        child: chip,
      );
    }

    return chip;
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

  Future<void> _openFollowList(int initialTab) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowListScreen(profile: _currentProfile, initialTab: initialTab),
      ),
    );
    if (!mounted) return;
    // Follows changed from the list (or the profiles opened from it) affect the counts.
    if (_isOwnProfile) {
      AuthService().fetchMyProfile();
    } else {
      final fresh = await AuthService().fetchUserProfile(_currentProfile.username);
      if (fresh != null && mounted) setState(() => _currentProfile = fresh);
    }
  }

  Widget _buildMetric(
    String number,
    String label,
    TextTheme textTheme,
    ColorScheme colorScheme, {
    VoidCallback? onTap,
  }) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
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
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }

  Widget _buildPostsStream(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoadingPosts && _userPosts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userPosts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchUserPosts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            Center(
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
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchUserPosts,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _userPosts.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        itemBuilder: (context, index) {
          final post = _userPosts[index];
          return PostCard(
            post: post,
            onAuthorTap: () {},
          );
        },
      ),
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
