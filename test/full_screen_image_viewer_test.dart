import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brote/widgets/full_screen_image_viewer.dart';

void main() {
  Widget buildHost() {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openFullScreenImage(
                context,
                imageUrl: 'https://example.com/foto.jpg',
                heroTag: 'img-1',
                title: 'Sofía',
                subtitle: '14:05',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('opens the photo full screen and closes with the close button', (tester) async {
    await tester.pumpWidget(buildHost());

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Sofía'), findsOneWidget);
    expect(find.text('14:05'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageViewer), findsNothing);
  });

  testWidgets('closes with the Escape key', (tester) async {
    await tester.pumpWidget(buildHost());

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenImageViewer), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageViewer), findsNothing);
  });

  testWidgets('dragging the photo down dismisses the viewer', (tester) async {
    await tester.pumpWidget(buildHost());

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 250));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageViewer), findsNothing);
  });

  testWidgets('a short drag snaps the photo back instead of closing', (tester) async {
    await tester.pumpWidget(buildHost());

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.timedDrag(
      find.byType(InteractiveViewer),
      const Offset(0, 40),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageViewer), findsOneWidget);
  });
}
