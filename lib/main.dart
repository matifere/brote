import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'services/auth_service.dart';
import 'theme/brote_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BroteApp());
}

class BroteApp extends StatelessWidget {
  const BroteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brote',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: BroteTheme.lightTheme(context),
      darkTheme: BroteTheme.darkTheme(context),
      home: const AuthGate(),
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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.eco_rounded,
                      size: 40,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
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

        final isAuthenticated = snapshot.data == true && AuthService().currentUser != null;

        if (isAuthenticated) {
          return MainNavigationScreen(profile: AuthService().currentUser!);
        } else {
          return const AuthScreen();
        }
      },
    );
  }
}
