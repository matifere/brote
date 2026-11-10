import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/main.dart';
import 'package:brote/services/auth_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthService().logout();
  });

  testWidgets('AuthScreen renders branding, tabs, and form fields', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Build our app and wait for AuthGate to resolve
    await tester.pumpWidget(const BroteApp());
    await tester.pumpAndSettle();

    // Verify app brand is present
    expect(find.text('brote'), findsWidgets);
    expect(find.text('Tu comunidad en tiempo real'), findsOneWidget);

    // Verify tabs are present
    expect(find.text('Iniciar Sesión'), findsOneWidget);
    expect(find.text('Registrarse'), findsOneWidget);

    // Initial state has Iniciar Sesión fields visible
    expect(find.text('Usuario o Correo'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);

    // Switch to Registrarse tab
    await tester.tap(find.text('Registrarse'));
    await tester.pumpAndSettle();

    // Verify register form fields are shown
    expect(find.text('Nombre Completo'), findsOneWidget);
    expect(find.text('Nombre de Usuario (@usuario)'), findsOneWidget);
    expect(find.text('Crear Cuenta'), findsOneWidget);

    // Ensure register button is visible and tap with empty fields to verify validation
    final submitButton = find.text('Crear Cuenta');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Ingresá tu nombre'), findsOneWidget);
  });

  testWidgets('AuthGate navigates to MainNavigationScreen with Feed, Search, Chats, and Profile', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Seed mock stored session
    SharedPreferences.setMockInitialValues({
      'brote_session_token': 'mock-valid-token-123',
      'brote_user_profile': jsonEncode({
        'id': 'test-uuid-001',
        'username': 'matifere',
        'displayName': 'Matias',
        'email': 'mati@brote.app',
      }),
    });

    // Launch app
    await tester.pumpWidget(const BroteApp());
    await tester.pumpAndSettle();

    // Verify MainNavigation destinations
    expect(find.text('Feed'), findsWidgets);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('Publicar'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);

    // Verify Feed elements are active
    expect(find.text('Para ti'), findsOneWidget);
    expect(find.text('Siguiendo'), findsOneWidget);

    // Navigate to Profile tab
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    // Verify Profile displays user identity
    expect(find.text('Matias'), findsWidgets);
    expect(find.text('@matifere'), findsWidgets);
    expect(find.text('Publicaciones'), findsWidgets);
  });
}
