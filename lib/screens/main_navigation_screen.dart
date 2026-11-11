import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../widgets/brote_logo.dart';
import 'auth_screen.dart';
import 'chats_screen.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final UserProfile profile;

  const MainNavigationScreen({super.key, required this.profile});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  List<UserProfile> _suggestedProfiles = [];
  bool _isLoadingSuggested = false;

  static const List<_NavItem> _navItems = [
    _NavItem(
      label: 'Feed',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _NavItem(
      label: 'Buscar',
      icon: Icons.search_rounded,
      selectedIcon: Icons.search_rounded,
    ),
    _NavItem(
      label: 'Publicar',
      icon: Icons.add_box_outlined,
      selectedIcon: Icons.add_box_rounded,
    ),
    _NavItem(
      label: 'Chats',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    _NavItem(
      label: 'Perfil',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pages = [
      FeedScreen(
        profile: widget.profile,
        onOpenProfile: () => _selectTab(4),
      ),
      const SearchScreen(),
      CreatePostScreen(
        profile: widget.profile,
        onPublished: () => _selectTab(0),
      ),
      const ChatsScreen(),
      ProfileScreen(profile: widget.profile),
    ];
    _loadSuggestedProfiles();
  }

  Future<void> _loadSuggestedProfiles() async {
    if (_isLoadingSuggested) return;
    _isLoadingSuggested = true;
    final list = await AuthService().getSuggestedProfiles();
    if (mounted) {
      setState(() {
        _suggestedProfiles = list;
        _isLoadingSuggested = false;
      });
    }
  }

  void _selectTab(int index) {
    if (index != _currentIndex) {
      if (index == 0) AuthService().postsRefreshNotifier.value++;
      if (index == 3) AuthService().chatsRefreshNotifier.value++;
      if (index == 4) AuthService().fetchMyProfile();
    }
    setState(() => _currentIndex = index);
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que querés salir de Brote?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;
        final isLargeDesktop = constraints.maxWidth >= 1000;
        final showRightSidebar = constraints.maxWidth >= 1150;

        // Mobile layout (< 720px)
        if (!isDesktop) {
          return Scaffold(
            body: IndexedStack(
              index: _currentIndex,
              children: _pages,
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: _selectTab,
              destinations: _navItems.map((item) {
                return NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                );
              }).toList(),
            ),
          );
        }

        // Desktop / Web layout (>= 720px)
        final maxGroupWidth = showRightSidebar ? 1260.0 : 960.0;

        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: Center(
            child: SizedBox(
              width: constraints.maxWidth.clamp(720.0, maxGroupWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Left Sidebar / Navigation Rail
                  _buildLeftSidebar(
                    isLarge: isLargeDesktop,
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),

                  // 2. Center Column (Constrained feed & content)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border.symmetric(
                          vertical: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                      ),
                      child: IndexedStack(
                        index: _currentIndex,
                        children: _pages,
                      ),
                    ),
                  ),

                  // 3. Right Sidebar (Suggestions & Shortcuts for screens >= 1150px)
                  if (showRightSidebar)
                    _buildRightSidebar(
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeftSidebar({
    required bool isLarge,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    final width = isLarge ? 240.0 : 80.0;

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 14 : 8,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isLarge ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          // Logo & Branding
          InkWell(
            onTap: () => _selectTab(0),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: isLarge ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment:
                    isLarge ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  const BroteLogo(size: 32, useDarkSquircle: true),
                  if (isLarge) ...[
                    const SizedBox(width: 10),
                    Text(
                      'brote',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Navigation Links
          for (var i = 0; i < _navItems.length; i++) ...[
            _buildNavItem(
              index: i,
              item: _navItems[i],
              isSelected: _currentIndex == i,
              isLarge: isLarge,
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            const SizedBox(height: 4),
          ],

          const SizedBox(height: 12),

          // Publicar Action Button
          if (isLarge)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: () => _selectTab(2),
                icon: const Icon(Icons.edit_note_rounded, size: 22),
                label: const Text(
                  'Nueva publicación',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            )
          else
            IconButton.filled(
              onPressed: () => _selectTab(2),
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Nueva publicación',
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.all(12),
              ),
            ),

          const Spacer(),

          // User Profile Tile at bottom
          ValueListenableBuilder<UserProfile?>(
            valueListenable: AuthService().currentUserNotifier,
            builder: (context, user, _) {
              final active = user ?? widget.profile;
              final avatar = active.avatarUrl;
              final name = active.displayName.isNotEmpty ? active.displayName : active.username;

              if (!isLarge) {
                return Tooltip(
                  message: '@${active.username}',
                  child: InkWell(
                    onTap: () => _selectTab(4),
                    borderRadius: BorderRadius.circular(24),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage: (avatar != null && avatar.isNotEmpty)
                          ? NetworkImage(avatar)
                          : null,
                      onBackgroundImageError: (avatar != null && avatar.isNotEmpty)
                          ? (_, _) {}
                          : null,
                      child: (avatar == null || avatar.isEmpty)
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            )
                          : null,
                    ),
                  ),
                );
              }

              return Material(
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: (avatar != null && avatar.isNotEmpty)
                        ? NetworkImage(avatar)
                        : null,
                    onBackgroundImageError: (avatar != null && avatar.isNotEmpty)
                        ? (_, _) {}
                        : null,
                    child: (avatar == null || avatar.isEmpty)
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '@${active.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                    onSelected: (val) {
                      if (val == 'profile') _selectTab(4);
                      if (val == 'logout') _handleLogout();
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'profile',
                        child: Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('Ver perfil'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                            SizedBox(width: 10),
                            Text('Cerrar sesión', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _selectTab(4),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required _NavItem item,
    required bool isSelected,
    required bool isLarge,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    final iconColor = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final icon = Icon(
      isSelected ? item.selectedIcon : item.icon,
      color: iconColor,
      size: 24,
    );

    if (!isLarge) {
      return Tooltip(
        message: item.label,
        child: InkWell(
          onTap: () => _selectTab(index),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: icon),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _selectTab(index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 14),
            Text(
              item.label,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightSidebar({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Container(
      width: 310,
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search shortcut
            InkWell(
              onTap: () => _selectTab(1),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text(
                      'Buscar en Brote',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // "A quién seguir" / Suggested Profiles
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people_outline_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'A quién seguir',
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _selectTab(1),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Ver más', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingSuggested)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_suggestedProfiles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No hay sugerencias en este momento.',
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    for (final user in _suggestedProfiles.take(4)) ...[
                      _buildSuggestedTile(user, colorScheme, textTheme),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Brote info footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'brote • Escritorio y Web',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tu comunidad en tiempo real. Hecho con ❤️ para compartir opiniones, cine y música.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedTile(
    UserProfile user,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final avatar = user.avatarUrl;
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProfileScreen(profile: user)),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              onBackgroundImageError: (avatar != null && avatar.isNotEmpty)
                  ? (_, _) {}
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                        fontSize: 14,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '@${user.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProfileScreen(profile: user)),
                );
              },
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: const Text('Ver', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}
