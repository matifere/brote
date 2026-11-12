import 'package:flutter/material.dart';
import 'models/user_profile.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'services/auth_service.dart';
import 'services/message_notification_service.dart';
import 'services/theme_service.dart';
import 'theme/brote_theme.dart';
import 'widgets/brote_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the saved light/dark choice before the first frame to avoid a flash
  await ThemeService().load();
  await MessageNotificationService().init();
  runApp(const BroteApp());
}

class BroteApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const BroteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().mode,
      builder: (context, themeMode, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Brote',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: BroteTheme.lightTheme(context),
        darkTheme: BroteTheme.darkTheme(context),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _autoLoginFuture;

  @override
  void initState() {
    super.initState();
    _autoLoginFuture = AuthService().tryAutoLogin();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _autoLoginFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final colorScheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: colorScheme.surface,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BroteLogo(size: 72, useDarkSquircle: true),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.data != true) {
          return const AuthScreen();
        }

        // The restored session is verified against Neon in the background; if it
        // turns out to be expired, AuthService logs out and we fall back to login
        // instead of leaving the user in an app where every request fails.
        return ValueListenableBuilder<UserProfile?>(
          valueListenable: AuthService().currentUserNotifier,
          builder: (context, user, _) {
            if (user == null || !AuthService().isAuthenticated) {
              return const AuthScreen();
            }
            return MainNavigationScreen(profile: user);
          },
        );
      },
    );
  }
}
