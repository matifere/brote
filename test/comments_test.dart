import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/post_item.dart';
import 'package:brote/screens/post_comments_screen.dart';
import 'package:brote/services/auth_service.dart';
import 'package:brote/widgets/post_card.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _me = {'id': 'me-1', 'username': 'ana', 'displayName': 'Ana'};

Map<String, dynamic> _comment(String id, String authorId, String name, String text) => {
      'id': id,
      'postId': 'post-1',
      'content': text,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String(),
      'author': {'id': authorId, 'username': name.toLowerCase(), 'displayName': name},
    };

PostItem _post({String authorId = 'other-1', int comments = 1}) => PostItem(
      id: 'post-1',
      authorId: authorId,
      authorName: authorId == 'me-1' ? 'Ana' : 'Beto',
      authorUsername: authorId == 'me-1' ? 'ana' : 'beto',
      content: 'Un post para comentar',
      commentsCount: comments,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'brote_session_token': 'tok',
      'brote_user_profile': jsonEncode(_me),
    });
  });

  Future<void> run(WidgetTester tester, MockClient server, Future<void> Function() body) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await http.runWithClient(() async {
      await tester.runAsync(() => AuthService().tryAutoLogin());
      await body();
    }, () => server);
    await tester.pumpWidget(const SizedBox());
    await AuthService().logout();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
  }

  testWidgets('lists, adds and deletes comments', (tester) async {
    final deleted = <String>[];
    final server = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/auth/me') return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
      if (path == '/api/posts/post-1/comments' && request.method == 'GET') {
        return _json({
          'success': true,
          'comments': [_comment('c1', 'other-2', 'Carla', 'Muy bueno')],
        });
      }
      if (path == '/api/posts/post-1/comments' && request.method == 'POST') {
        final text = (jsonDecode(request.body) as Map<String, dynamic>)['content'] as String;
        return _json({'success': true, 'comment': _comment('c2', 'me-1', 'Ana', text), 'commentsCount': 2});
      }
      if (path == '/api/posts/post-1/comments/c2' && request.method == 'DELETE') {
        deleted.add('c2');
        return _json({'success': true, 'commentsCount': 1});
      }
      return http.Response('404 Not Found', 404);
    });

    await run(tester, server, () async {
      await tester.pumpWidget(MaterialApp(home: PostCommentsScreen(post: _post())));
      await settle(tester);

      expect(find.text('Muy bueno'), findsOneWidget);
      // Only your own comments (or any on your post) can be deleted
      expect(find.byTooltip('Borrar comentario'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Coincido');
      await tester.tap(find.byTooltip('Comentar'));
      await settle(tester);
      expect(find.text('Coincido'), findsOneWidget);

      await tester.tap(find.byTooltip('Borrar comentario'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
      await settle(tester);
      expect(deleted, ['c2']);
      expect(find.text('Coincido'), findsNothing);
    });
  });

  testWidgets('says when the server has no comments yet', (tester) async {
    final server = MockClient((request) async {
      if (request.url.path == '/api/auth/me') {
        return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
      }
      return http.Response('404 Not Found', 404);
    });

    await run(tester, server, () async {
      await tester.pumpWidget(MaterialApp(home: PostCommentsScreen(post: _post())));
      await settle(tester);

      expect(find.text('Los comentarios todavía no están disponibles'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });

  testWidgets('your own posts can be deleted and there is no fake repost button', (tester) async {
    final deletedPosts = <String>[];
    final server = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/auth/me') return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
      if (path == '/api/posts/post-1' && request.method == 'DELETE') {
        deletedPosts.add('post-1');
        return _json({'success': true});
      }
      return http.Response('404 Not Found', 404);
    });

    await run(tester, server, () async {
      final refreshesBefore = AuthService().postsRefreshNotifier.value;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PostCard(post: _post(authorId: 'me-1')))));
      await settle(tester);

      expect(find.byIcon(Icons.repeat_rounded), findsNothing);

      await tester.tap(find.byTooltip('Opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar publicación').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
      await settle(tester);

      expect(deletedPosts, ['post-1']);
      expect(AuthService().postsRefreshNotifier.value, refreshesBefore + 1);
      expect(find.text('Publicación borrada'), findsOneWidget);

      // Someone else's post has no options menu
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PostCard(post: _post()))));
      await settle(tester);
      expect(find.byTooltip('Opciones'), findsNothing);
    });
  });

  testWidgets('threads replies under parent comments and sends parentId when replying', (tester) async {
    String? receivedParentId;
    final server = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/auth/me') return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
      if (path == '/api/posts/post-1/comments' && request.method == 'GET') {
        return _json({
          'success': true,
          'comments': [_comment('c1', 'other-2', 'Carla', 'Buenisimo esto')],
        });
      }
      if (path == '/api/posts/post-1/comments' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        receivedParentId = body['parentId'] as String?;
        final text = body['content'] as String;
        final reply = _comment('c2', 'me-1', 'Ana', text);
        reply['parentId'] = receivedParentId;
        reply['replyToUsername'] = 'carla';
        return _json({'success': true, 'comment': reply, 'commentsCount': 2});
      }
      return http.Response('404 Not Found', 404);
    });

    await run(tester, server, () async {
      await tester.pumpWidget(MaterialApp(home: PostCommentsScreen(post: _post())));
      await settle(tester);

      expect(find.text('Buenisimo esto'), findsOneWidget);
      expect(find.text('Responder'), findsOneWidget);

      // Tap Responder
      await tester.tap(find.text('Responder'));
      await settle(tester);

      expect(find.text('Respondiendo a @carla'), findsOneWidget);

      // Enter reply text and send
      await tester.enterText(find.byType(TextField), 'Coincido Carla');
      await tester.tap(find.byTooltip('Comentar'));
      await settle(tester);

      expect(receivedParentId, 'c1');
      expect(find.text('Coincido Carla'), findsOneWidget);
      expect(find.text('Respondiendo a @carla'), findsOneWidget);
    });
  });

  testWidgets('likes and unlikes comments with instant toggle', (tester) async {
    int likeCalls = 0;
    final server = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/auth/me') return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
      if (path == '/api/posts/post-1/comments' && request.method == 'GET') {
        return _json({
          'success': true,
          'comments': [
            {
              ..._comment('c1', 'other-2', 'Carla', 'Genial'),
              'likesCount': 0,
              'isLiked': false,
            }
          ],
        });
      }
      if (path == '/api/posts/post-1/comments/c1/like' && request.method == 'POST') {
        likeCalls++;
        return _json({'success': true, 'isLiked': likeCalls % 2 == 1, 'likesCount': likeCalls % 2 == 1 ? 1 : 0});
      }
      return http.Response('404 Not Found', 404);
    });

    await run(tester, server, () async {
      await tester.pumpWidget(MaterialApp(home: PostCommentsScreen(post: _post())));
      await settle(tester);

      expect(find.text('Genial'), findsOneWidget);
      // PostCard has its own like button, so comment like button is the last
      final commentLikeButton = find.byIcon(Icons.favorite_border_rounded).last;
      expect(commentLikeButton, findsOneWidget);
      expect(find.text('1'), findsNothing);

      // Tap heart to like
      await tester.tap(commentLikeButton);
      await settle(tester);

      expect(likeCalls, 1);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Tap heart again to unlike
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await settle(tester);

      expect(likeCalls, 2);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
      expect(find.text('1'), findsNothing);
    });
  });
}
