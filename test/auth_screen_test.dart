import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brote/main.dart';

void main() {
  testWidgets('AuthScreen renders branding, tabs, and form fields', (WidgetTester tester) async {
    // Set a phone-like viewport
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Build our app and trigger a frame.
    await tester.pumpWidget(const BroteApp());

    // Verify app brand is present
    expect(find.text('brote'), findsOneWidget);
    expect(find.text('Tu comunidad en tiempo real'), findsOneWidget);

    // Verify tabs are present
    expect(find.text('Iniciar Sesión'), findsOneWidget);
    expect(find.text('Registrarse'), findsOneWidget);

    // Initial state is Iniciar Sesión tab
    expect(find.text('Usuario o Correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
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
}
