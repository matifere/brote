import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/rating.dart';
import 'package:brote/screens/create_post_screen.dart';
import 'package:brote/services/auth_service.dart';
import 'package:brote/services/catalog_service.dart';
import 'package:brote/widgets/review_picker.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().logout();
  });

  testWidgets('ReviewDraftCard reports the tapped star', (tester) async {
    var stars = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReviewDraftCard(
              item: const CatalogItem(category: RatingCategory.movie, title: 'Dune', year: 2021),
              stars: stars,
              onStarsChanged: (value) => setState(() => stars = value),
              onChange: () {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Reseña de película'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Tocá las estrellas'), findsOneWidget);

    await tester.tap(find.byTooltip('4 estrellas'));
    await tester.pump();

    expect(stars, 4);
    expect(find.text('Muy buena'), findsOneWidget);
  });

  testWidgets('Publicar lets you attach a review and asks for stars before posting', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: CreatePostScreen()));

    // Open the picker, switch to music and search
    await tester.tap(find.text('Reseña'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewItemPickerScreen), findsOneWidget);

    await tester.tap(find.text('Música'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Abbey Road');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // The catalog isn't reachable in tests; the typed title is always offered
    await tester.tap(find.text('Reseñar "Abbey Road"'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewItemPickerScreen), findsNothing);
    expect(find.text('Reseña de música'), findsOneWidget);
    expect(find.text('Abbey Road'), findsOneWidget);
    expect(find.text('Cambiar reseña'), findsOneWidget);

    // Publishing without stars is blocked
    await tester.tap(find.text('Publicar'));
    await tester.pump();
    expect(find.text('Elegí de 1 a 5 estrellas para tu reseña.'), findsOneWidget);

    await tester.tap(find.byTooltip('5 estrellas'));
    await tester.pump();
    expect(find.text('Excelente'), findsOneWidget);

    // Removing the review brings back the regular composer
    await tester.tap(find.byTooltip('Quitar reseña'));
    await tester.pump();
    expect(find.text('Reseña de música'), findsNothing);
    expect(find.text('Reseña'), findsOneWidget);
  });
}
