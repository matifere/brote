import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/screens/search_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SearchScreen renders search field and no static mock trends or accounts', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify search input field is rendered
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Buscar por nombre o @usuario...'), findsOneWidget);

    // Verify mock items from previous version are completely gone
    expect(find.text('#Tecnologia'), findsNothing);
    expect(find.text('#MusicaEnVivo'), findsNothing);
    expect(find.text('Lucía Benítez'), findsNothing);
    expect(find.text('Lucas Albarracín'), findsNothing);
    expect(find.text('Multimedia popular'), findsNothing);
    expect(find.text('Tendencias para ti'), findsNothing);
  });
}
