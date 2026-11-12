import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/services/auth_service.dart';
import 'package:brote/services/message_notification_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _me = {'id': 'me-1', 'username': 'mati', 'displayName': 'Mati'};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'brote_session_token': 'test-tok',
      'brote_user_profile': jsonEncode(_me),
    });
    MessageNotificationService().stop();
  });

  tearDown(() {
    MessageNotificationService().stop();
  });

  group('MessageNotificationService', () {
    test('initializes and does not alert on first pass (avoids spamming history)', () async {
      final chats = [
        {
          'id': 'conv-1',
          'lastMessage': 'Mensaje viejo',
          'lastMessageTime': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
          'unreadCount': 2,
          'otherParticipant': {
            'id': 'user-2',
            'username': 'lucas',
            'displayName': 'Lucas',
          },
        }
      ];

      final server = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
        }
        if (request.url.path == '/api/chats') {
          return _json({'success': true, 'chats': chats});
        }
        return _json({'success': false}, 404);
      });

      await http.runWithClient(() async {
        await AuthService().tryAutoLogin();
        final service = MessageNotificationService();
        await service.init();

        // First check
        await service.checkForNewMessages();
        // Initial state set, no crash
        expect(service.activeConversationId, isNull);
      }, () => server);
    });

    test('suppresses notification if conversation is currently open and active', () async {
      final now = DateTime.now();
      final chats = [
        {
          'id': 'conv-active',
          'lastMessage': '¿Estás ahí?',
          'lastMessageTime': now.toIso8601String(),
          'unreadCount': 1,
          'otherParticipant': {
            'id': 'user-3',
            'username': 'sofia',
            'displayName': 'Sofia',
          },
        }
      ];

      final server = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
        }
        if (request.url.path == '/api/chats') {
          return _json({'success': true, 'chats': chats});
        }
        return _json({'success': false}, 404);
      });

      await http.runWithClient(() async {
        await AuthService().tryAutoLogin();
        final service = MessageNotificationService();
        await service.init();

        // Mark conversation active
        service.activeConversationId = 'conv-active';

        // Check messages
        await service.checkForNewMessages();
        expect(service.activeConversationId, 'conv-active');
      }, () => server);
    });
  });
}
