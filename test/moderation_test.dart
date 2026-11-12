import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/post_item.dart';
import 'package:brote/models/report_item.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/admin_moderation_screen.dart';
import 'package:brote/services/auth_service.dart';
import 'package:brote/widgets/post_card.dart';
import 'package:brote/widgets/report_dialog.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _adminProfile = {
  'id': 'admin-uuid-1',
  'username': 'mati',
  'displayName': 'Mati Admin',
  'role': 'admin',
  'isSuspended': false,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'brote_session_token': 'test-admin-token',
      'brote_user_profile': jsonEncode(_adminProfile),
    });
  });

  group('Pilar 1 & 4 Models: UserProfile and PostItem moderation fields', () {
    test('UserProfile deserializes role, isAdmin, and isSuspended', () {
      final admin = UserProfile.fromJson({
        'id': 'u1',
        'username': 'mati',
        'displayName': 'Matias',
        'role': 'admin',
        'isSuspended': false,
        'isBlocked': false,
      });
      expect(admin.role, 'admin');
      expect(admin.isAdmin, isTrue);
      expect(admin.isSuspended, isFalse);

      final regularUser = UserProfile.fromJson({
        'id': 'u2',
        'username': 'pedro',
        'displayName': 'Pedro',
        'role': 'user',
        'isSuspended': true,
        'isBlocked': true,
      });
      expect(regularUser.role, 'user');
      expect(regularUser.isAdmin, isFalse);
      expect(regularUser.isSuspended, isTrue);
      expect(regularUser.isBlocked, isTrue);
    });

    test('PostItem deserializes isSensitive, isHidden, and reportsCount', () {
      final post = PostItem.fromJson({
        'id': 'p-mod-1',
        'authorId': 'u-author',
        'authorUsername': 'author',
        'authorName': 'Author User',
        'content': 'Contenido de prueba',
        'createdAt': DateTime.now().toIso8601String(),
        'isSensitive': true,
        'isHidden': true,
        'reportsCount': 3,
      });
      expect(post.isSensitive, isTrue);
      expect(post.isHidden, isTrue);
      expect(post.reportsCount, 3);
    });

    test('ReportItem deserializes with post preview', () {
      final report = ReportItem.fromJson({
        'id': 'rep-1',
        'reason': 'explicit',
        'details': 'Foto no adecuada',
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
        'post': {
          'id': 'post-100',
          'content': 'Post reportado',
          'imageUrl': 'https://example.com/img.jpg',
          'isSensitive': false,
          'isHidden': false,
          'reportsCount': 1,
          'authorId': 'target-user',
          'authorUsername': 'baduser',
          'authorName': 'Bad User',
        },
      });

      expect(report.id, 'rep-1');
      expect(report.reasonLabel, 'Contenido explícito');
      expect(report.post, isNotNull);
      expect(report.post!.authorUsername, 'baduser');
      expect(report.post!.reportsCount, 1);
    });
  });

  group('Pilar 2: Sensitive content blur and reveal in PostCard', () {
    testWidgets('shows sensitive badge and blur cover with tap to reveal', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sensitivePost = PostItem(
        id: 'p-sens-1',
        authorId: 'other-user',
        authorUsername: 'foto_fan',
        authorName: 'Foto Fan',
        content: 'Mirá esta foto sensible',
        imageUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475',
        isSensitive: true,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PostCard(post: sensitivePost),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check "Sensible" tag in post header
      expect(find.text('Sensible'), findsOneWidget);

      // Check sensitive cover overlay button
      expect(find.text('Contenido sensible · Mostrar'), findsOneWidget);

      // Tap on the cover button to reveal media
      await tester.tap(find.text('Contenido sensible · Mostrar'));
      await tester.pumpAndSettle();

      // After reveal, the cover overlay is gone
      expect(find.text('Contenido sensible · Mostrar'), findsNothing);
    });
  });

  group('Pilar 3: Report dialog and user blocking', () {
    testWidgets('Report dialog sends report with selected reason', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? sentReason;
      String? sentPostId;

      final server = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return _json({'success': true, 'token': 'tok', 'user': _adminProfile, 'profile': _adminProfile});
        }
        if (request.url.path == '/api/reports' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentReason = body['reason'] as String?;
          sentPostId = body['postId'] as String?;
          return _json({'success': true, 'reportId': 'rep-new-1', 'message': 'Reporte enviado con éxito'});
        }
        return _json({'success': false}, 404);
      });

      await http.runWithClient(() async {
        await tester.runAsync(() => AuthService().tryAutoLogin());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () => showReportContentDialog(
                      ctx,
                      postId: 'post-test-1',
                      targetTitle: 'publicación',
                    ),
                    child: const Text('Reportar'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Reportar'));
        await tester.pumpAndSettle();

        expect(find.text('Reportar publicación'), findsOneWidget);

        // Select the explicit content reason
        await tester.tap(find.text('Contenido explícito (+18) sin marcar'));
        await tester.pumpAndSettle();

        // Submit
        await tester.tap(find.widgetWithText(FilledButton, 'Enviar reporte'));
        await tester.pumpAndSettle();

        expect(sentReason, 'explicit');
        expect(sentPostId, 'post-test-1');
        expect(find.text('Reporte enviado con éxito'), findsOneWidget);
      }, () => server);
    });

    testWidgets('blockUser service call invokes POST /api/users/:id/block', (tester) async {
      bool blockCalled = false;
      final server = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return _json({'success': true, 'token': 'tok', 'user': _adminProfile, 'profile': _adminProfile});
        }
        if (request.url.path == '/api/users/user-to-block/block' && request.method == 'POST') {
          blockCalled = true;
          return _json({'success': true});
        }
        return _json({'success': false}, 404);
      });

      await http.runWithClient(() async {
        await tester.runAsync(() => AuthService().tryAutoLogin());
        final ok = await AuthService().blockUser('user-to-block');
        expect(ok, isTrue);
        expect(blockCalled, isTrue);
      }, () => server);
    });
  });

  group('Pilar 4: Admin Moderation Screen', () {
    testWidgets('renders reports and allows taking moderation actions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? performedAction;
      final server = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/auth/me') {
          return _json({'success': true, 'token': 'tok', 'user': _adminProfile, 'profile': _adminProfile});
        }
        if (path == '/api/admin/reports' && request.method == 'GET') {
          return _json({
            'success': true,
            'reports': [
              {
                'id': 'rep-admin-1',
                'reporterId': 'u-rep',
                'reporterUsername': 'juan',
                'reporterName': 'Juan',
                'targetType': 'post',
                'targetPostId': 'p-bad',
                'reason': 'harassment',
                'details': 'Insultos reiterados',
                'status': 'pending',
                'createdAt': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
                'post': {
                  'id': 'p-bad',
                  'content': 'Publicación con contenido ofensivo',
                  'imageUrl': null,
                  'isSensitive': false,
                  'isHidden': false,
                  'reportsCount': 3,
                  'authorId': 'u-bad',
                  'authorUsername': 'ofensivo',
                  'authorName': 'Usuario Ofensivo',
                },
              }
            ],
          });
        }
        if (path == '/api/admin/reports/rep-admin-1/action' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          performedAction = body['action'] as String?;
          return _json({'success': true});
        }
        return _json({'success': false}, 404);
      });

      await http.runWithClient(() async {
        await tester.runAsync(() => AuthService().tryAutoLogin());

        await tester.pumpWidget(
          const MaterialApp(
            home: AdminModerationScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Verify dashboard title and tabs
        expect(find.text('Panel de Moderación'), findsOneWidget);
        expect(find.text('Pendientes'), findsOneWidget);
        expect(find.text('Acoso u odio'), findsOneWidget);
        expect(find.text('Publicación con contenido ofensivo'), findsOneWidget);

        // Verify action buttons
        expect(find.text('Desestimar'), findsOneWidget);
        expect(find.text('Ocultar'), findsOneWidget);
        expect(find.text('Eliminar'), findsOneWidget);
        expect(find.text('Suspender usuario'), findsOneWidget);

        // Tap "Ocultar" action button
        await tester.tap(find.text('Ocultar'));
        await tester.pumpAndSettle();

        // Confirm in dialog
        await tester.tap(find.widgetWithText(FilledButton, 'Ocultar'));
        await tester.pumpAndSettle();

        expect(performedAction, 'hide');
        expect(find.text('Acción "Ocultar" aplicada correctamente.'), findsOneWidget);
      }, () => server);
    });
  });
}
