import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';

void main() {
  runApp(const BroteApp());
}

class BroteApp extends StatelessWidget {
  const BroteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Definición de ColorScheme semilla para 'brote' (verde natural)
    const seedColor = Color(0xFF2E7D32);

    return MaterialApp(
      title: 'Brote',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthScreen(),
    );
  }
}
