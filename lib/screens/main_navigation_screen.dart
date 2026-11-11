import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/chat_unread_service.dart';
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

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      FeedScreen(
        profile: widget.profile,
        onOpenProfile: () => setState(() => _currentIndex = 4),
      ),
      const SearchScreen(),
      CreatePostScreen(
        profile: widget.profile,
        onPublished: () => setState(() => _currentIndex = 0),
      ),
      const ChatsScreen(),
      ProfileScreen(profile: widget.profile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: ChatUnreadService().unreadChats,
        builder: (context, unreadChats, _) => NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            // Tabs live in an IndexedStack and never rebuild from scratch, so
            // refresh them when entering (e.g. after following someone).
            if (index != _currentIndex) {
              if (index == 0) AuthService().postsRefreshNotifier.value++;
              if (index == 3) AuthService().chatsRefreshNotifier.value++;
              if (index == 4) AuthService().fetchMyProfile(); // follower/following counts
            }
            setState(() => _currentIndex = index);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Feed',
            ),
            const NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'Buscar',
            ),
            const NavigationDestination(
              icon: Icon(Icons.add_box_outlined),
              selectedIcon: Icon(Icons.add_box_rounded),
              label: 'Publicar',
            ),
            NavigationDestination(
              icon: _withUnreadBadge(const Icon(Icons.chat_bubble_outline_rounded), unreadChats),
              selectedIcon: _withUnreadBadge(const Icon(Icons.chat_bubble_rounded), unreadChats),
              tooltip: unreadChats == 0
                  ? null
                  : unreadChats == 1
                      ? 'Chats: 1 conversación sin leer'
                      : 'Chats: $unreadChats conversaciones sin leer',
              label: 'Chats',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }

  Widget _withUnreadBadge(Widget icon, int unreadChats) => Badge(
        isLabelVisible: unreadChats > 0,
        label: Text(unreadChats > 99 ? '99+' : '$unreadChats'),
        child: icon,
      );
}
