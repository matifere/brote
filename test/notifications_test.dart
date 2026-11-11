import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/app_notification.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/feed_screen.dart';
import 'package:brote/screens/notifications_screen.dart';
import 'package:brote/services/auth_service.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _me = {'id': 'me-1', 'username': 'ana', 'displayName': 'Ana'};

Map<String, dynamic> _post(String id, String content) => {
      'id': id,
      'authorId': 'u-$id',
      'authorName': 'Autor $id',
      'authorUsername': 'autor$id',
      'content': content,
      'createdAt': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    };

void main() {
  group('AppNotification', () {
    test('reads the API payload and describes what happened', () {
      final like = AppNotification.fromJson({
        'id': 'n1',
        'type': 'like',
        'createdAt': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
        'isRead': false,
        'postContent': '🎬 Dune (2021) ★★★★☆\n\nMuy buena.',
        'actor': {'id': 'u1', 'username': 'beto', 'displayName': 'Beto'},
      });
      expect(like.kind, NotificationKind.like);
      expect(like.actor.displayName, 'Beto');
      expect(like.message, 'le dio me gusta a tu publicación');
      expect(like.postPreview, 'Reseña de Dune');
      expect(like.timeAgo, 'hace 5 m');

      final follow = AppNotification.fromJson({
        'id': 'n2',
        'type': 'follow_request',
        'actor': {'id': 'u2', 'username': 'carla', 'displayName': 'Carla'},
      });
      expect(follow.message, 'quiere seguirte');
      expect(follow.postPreview, isNull);

      final longPost = AppNotification.fromJson({
        'id': 'n3',
        'type': 'like',
        'postContent': '${'a' * 120}\nsegunda línea',
        'actor': {'id': 'u1', 'username': 'beto', 'displayName': 'Beto'},
      });
      expect(longPost.postPreview!.length, 80);
      expect(AppNotification.fromJson({'id': 'n4', 'type': 'nuevo', 'actor': {}}).kind, NotificationKind.unknown);
    });
  });

  group('Notifications UI', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'brote_session_token': 'tok',
        'brote_user_profile': jsonEncode(_me),
      });
    });

    Future<void> run(WidgetTester tester, MockClient server, Widget screen) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await http.runWithClient(() async {
        await tester.runAsync(() => AuthService().tryAutoLogin());
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pumpAndSettle();
      }, () => server);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await AuthService().logout();
    }

    testWidgets('lists server notifications and marks them as read', (tester) async {
      var markedRead = false;
      final server = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/auth/me') return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
        if (path == '/api/notifications') {
          return _json({
            'success': true,
            'unreadCount': 2,
            'notifications': [
              {
                'id': 'n1',
                'type': 'like',
                'isRead': false,
                'postContent': 'Mi primer post',
                'actor': {'id': 'u1', 'username': 'beto', 'displayName': 'Beto'},
              },
              {
                'id': 'n2',
                'type': 'follow',
                'isRead': false,
                'actor': {'id': 'u2', 'username': 'carla', 'displayName': 'Carla'},
              },
            ],
          });
        }
        if (path == '/api/notifications/read' && request.method == 'POST') {
          markedRead = true;
          return _json({'success': true});
        }
        return http.Response('404 Not Found', 404);
      });

      await run(tester, server, const NotificationsScreen());

      expect(find.textContaining('le dio me gusta a tu publicación', findRichText: true), findsOneWidget);
      expect(find.textContaining('empezó a seguirte', findRichText: true), findsOneWidget);
      expect(find.textContaining('"Mi primer post"'), findsOneWidget);
      expect(find.textContaining('Por ahora ves solicitudes'), findsNothing);
      expect(markedRead, isTrue);

      await finish(tester);
    });

    testWidgets('without the endpoints it shows follow requests and unread chats', (tester) async {
      final server = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/auth/me') return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
        if (path == '/api/profile/me/follow-requests') {
          return _json({
            'success': true,
            'requests': [
              {'id': 'u3', 'username': 'dani', 'displayName': 'Dani'},
            ],
          });
        }
        if (path == '/api/chats') {
          return _json({
            'success': true,
            'chats': [
              {
                'id': 'conv-1',
                'lastMessage': 'hola',
                'unreadCount': 2,
                'otherParticipant': {'id': 'u4', 'username': 'eva', 'displayName': 'Eva'},
              },
              {
                'id': 'conv-2',
                'lastMessage': 'leído',
                'unreadCount': 0,
                'otherParticipant': {'id': 'u5', 'username': 'fede', 'displayName': 'Fede'},
              },
            ],
          });
        }
        return http.Response('404 Not Found', 404);
      });

      await run(tester, server, const NotificationsScreen());

      expect(find.textContaining('Por ahora ves solicitudes'), findsOneWidget);
      expect(find.textContaining('quiere seguirte', findRichText: true), findsOneWidget);
      expect(find.textContaining('te envió un mensaje', findRichText: true), findsOneWidget);
      expect(find.textContaining('Fede', findRichText: true), findsNothing);

      await finish(tester);
    });

    testWidgets('the feed has a reviews tab and the notifications bell', (tester) async {
      final server = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/auth/me') return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
        // An older server ignores ?filter=reviews and returns the whole feed
        if (path == '/api/posts/feed') {
          return _json({
            'success': true,
            'posts': [
              _post('1', '🎵 Abbey Road — The Beatles ★★★★★\n\nUn discazo.'),
              _post('2', 'Un post común'),
            ],
          });
        }
        return http.Response('404 Not Found', 404);
      });

      await run(
        tester,
        server,
        FeedScreen(profile: const UserProfile(id: 'me-1', username: 'ana', displayName: 'Ana'), onOpenProfile: () {}),
      );

      expect(find.byTooltip('Notificaciones'), findsOneWidget);
      expect(find.text('Un post común'), findsOneWidget);

      await http.runWithClient(() async {
        await tester.tap(find.text('Reseñas'));
        await tester.pumpAndSettle();
      }, () => server);

      expect(find.text('Reseña de música'), findsOneWidget);
      expect(find.textContaining('Un discazo.', findRichText: true), findsOneWidget);
      expect(find.text('Un post común'), findsNothing);

      await finish(tester);
    });
  });
}
