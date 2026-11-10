import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/follow_requests_screen.dart';
import 'package:brote/screens/profile_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('FollowRequestsScreen displays title and empty state', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: FollowRequestsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Solicitudes de seguimiento'), findsOneWidget);
    expect(find.text('No tenés solicitudes pendientes'), findsOneWidget);
  });

  testWidgets('ProfileScreen renders follow requests banner for private profile with requests', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const privateProfile = UserProfile(
      id: 'test-user-private',
      username: 'mati_private',
      displayName: 'Matias Privado',
      isPrivate: true,
      pendingRequestsCount: 2,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(profile: privateProfile),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Solicitudes de seguimiento'), findsWidgets);
    expect(find.text('2 personas quieren seguirte'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
  });
}
