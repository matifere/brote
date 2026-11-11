import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/follow_list_screen.dart';
import 'package:brote/services/auth_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().logout();
  });

  testWidgets('FollowListScreen shows both tabs and opens on the requested one', (tester) async {
    const profile = UserProfile(
      id: 'other-1',
      username: 'sofia_v',
      displayName: 'Sofía Valenzuela',
      followersCount: 3,
      followingCount: 5,
    );

    await tester.pumpWidget(
      const MaterialApp(home: FollowListScreen(profile: profile, initialTab: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sofía Valenzuela'), findsOneWidget);
    expect(find.text('3 Seguidores'), findsOneWidget);
    expect(find.text('5 Siguiendo'), findsOneWidget);

    // Without a followers endpoint, another user's lists can't be built client-side.
    expect(find.text('Todavía no disponible'), findsOneWidget);
  });
}
