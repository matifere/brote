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

  testWidgets('shows an image that is already in memory', (tester) async {
    // 1x1 transparent PNG, like a decrypted chat photo
    final bytes = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    final image = MemoryImage(bytes);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openFullScreenImage(
                context,
                image: image,
                heroTag: 'img-mem',
                thumbnailCacheWidth: 220,
                title: 'Sofía',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageViewer), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Image && w.image == image), findsOneWidget);
    expect(find.text('No se pudo cargar la imagen'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenImageViewer), findsNothing);
  });

  test('needs exactly one of imageUrl or image', () {
    expect(() => FullScreenImageViewer(heroTag: 'x'), throwsAssertionError);
    expect(
      () => FullScreenImageViewer(
        heroTag: 'x',
        imageUrl: 'https://example.com/foto.jpg',
        image: MemoryImage(Uint8List(0)),
      ),
      throwsAssertionError,
    );
  });
}
