import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/edit_profile_screen.dart';
import 'package:brote/screens/profile_screen.dart';
import 'package:brote/services/auth_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testProfile = UserProfile(
    id: 'test-uuid-456',
    username: 'mati',
    displayName: 'Matias',
    bio: 'Desarrollador de software y apasionado por la tecnología.',
    avatarUrl: null,
  );

  testWidgets('ProfileScreen displays user details and opens EditProfileScreen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(profile: testProfile),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Matias'), findsWidgets);
    expect(find.text('@mati'), findsWidgets);
    expect(find.text('Desarrollador de software y apasionado por la tecnología.'), findsOneWidget);
    expect(find.text('Editar perfil'), findsOneWidget);

    // Tap 'Editar perfil'
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();

    // Verify EditProfileScreen is pushed
    expect(find.text('Editar perfil'), findsWidgets);
    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Biografía / Descripción'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Cambiar foto de perfil'), findsOneWidget);
  });

  testWidgets('EditProfileScreen allows editing fields and opens avatar picker', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: EditProfileScreen(profile: testProfile),
      ),
    );
    await tester.pumpAndSettle();

    // Initial fields have user data
    expect(find.widgetWithText(TextFormField, 'Matias'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '@mati'), findsOneWidget);

    // Open avatar picker
    await tester.tap(find.text('Cambiar foto de perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Foto de perfil'), findsOneWidget);
    expect(find.text('Avatares destacados'), findsOneWidget);
    expect(find.text('Ingresar URL personalizada'), findsOneWidget);
  });
}
