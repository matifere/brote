import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:brote/models/post_item.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/widgets/post_card.dart';
import 'package:brote/screens/create_post_screen.dart';
import 'package:brote/screens/feed_screen.dart';

void main() {
  testWidgets('PostCard renders Markdown content including code snippets', (tester) async {
    final post = PostItem(
      id: 'test-1',
      authorId: 'user-1',
      authorName: 'Mati Dev',
      authorUsername: 'mati',
      content: 'Hola mundo!\n```dart\nvoid main() => print("Brote");\n```',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      likesCount: 10,
      isLiked: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(post: post),
        ),
      ),
    );

    expect(find.text('Mati Dev'), findsOneWidget);
    expect(find.text('@mati'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('CreatePostScreen allows text input, preview toggle, and image button', (tester) async {
    final testProfile = UserProfile(
      id: 'me-1',
      username: 'mati',
      displayName: 'Mati',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CreatePostScreen(profile: testProfile),
      ),
    );

    expect(find.text('Nueva publicación'), findsOneWidget);
    expect(find.text('Publicar'), findsOneWidget);
    expect(find.text('Agregar foto'), findsOneWidget);

    // Enter markdown text
    await tester.enterText(
      find.byType(TextField),
      'Probando **Markdown** y `código`',
    );
    await tester.pump();

    // Verify "Vista previa" button is now visible
    expect(find.text('Vista previa'), findsOneWidget);

    // Tap "Vista previa"
    await tester.tap(find.text('Vista previa'));
    await tester.pump();

    // Verify preview is displayed with MarkdownBody
    expect(find.text('Editar'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('FeedScreen renders Para ti and Siguiendo tabs', (tester) async {
    final testProfile = UserProfile(
      id: 'me-1',
      username: 'mati',
      displayName: 'Mati',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeedScreen(
          profile: testProfile,
          onOpenProfile: () {},
        ),
      ),
    );

    expect(find.text('Para ti'), findsOneWidget);
    expect(find.text('Siguiendo'), findsOneWidget);
  });
}
