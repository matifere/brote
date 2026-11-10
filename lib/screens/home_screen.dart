import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'main_navigation_screen.dart';

class HomeScreen extends StatelessWidget {
  final UserProfile profile;

  const HomeScreen({
    super.key,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return MainNavigationScreen(profile: profile);
  }
}
