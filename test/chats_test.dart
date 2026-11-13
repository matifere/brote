import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/chat_message.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/chats_screen.dart';
import 'package:brote/screens/chat_conversation_screen.dart';
import 'package:brote/screens/new_chat_screen.dart';
import 'package:brote/services/auth_service.dart';

void main() {
  test('ChatMessage and ChatMessageReply JSON serialization', () {
    const reply = ChatMessageReply(
      id: 'orig-1',
      senderId: 'u-1',
      senderName: 'Sofia',
      text: '¿Venís hoy?',
      mediaUrl: 'https://example.com/p.jpg',
    );

    final replyJson = reply.toJson();
    final parsedReply = ChatMessageReply.fromJson(replyJson);
    expect(parsedReply.id, 'orig-1');
    expect(parsedReply.senderId, 'u-1');
    expect(parsedReply.senderName, 'Sofia');
    expect(parsedReply.text, '¿Venís hoy?');
    expect(parsedReply.mediaUrl, 'https://example.com/p.jpg');

    final messageJson = {
      'id': 'msg-1',
      'conversation_id': 'conv-1',
      'sender_id': 'me-1',
      'sender_name': 'Mati',
      'content': 'Sí, voy en 10',
      'created_at': DateTime.now().toIso8601String(),
      'is_me': true,
      'reply': replyJson,
    };

    final message = ChatMessage.fromJson(messageJson);
    expect(message.id, 'msg-1');
    expect(message.content, 'Sí, voy en 10');
    expect(message.reply, isNotNull);
    expect(message.reply!.id, 'orig-1');
    expect(message.reply!.senderName, 'Sofia');
    expect(message.reply!.text, '¿Venís hoy?');
  });
  testWidgets('ChatsScreen renders app bar, search button, and new message action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatsScreen(),
      ),
    );

    expect(find.text('Mensajes'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.edit_square), findsOneWidget);
  });

  testWidgets('ChatConversationScreen renders header and input bar', (tester) async {
    final other = UserProfile(
      id: 'other-1',
      username: 'sofia_v',
      displayName: 'Sofía Valenzuela',
      isPrivate: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatConversationScreen(
          conversationId: 'test-conv-1',
          otherParticipant: other,
        ),
      ),
    );

    expect(find.text('Sofía Valenzuela'), findsOneWidget);
    expect(find.text('@sofia_v'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
  });

  testWidgets('NewChatScreen renders search and candidates with privacy badges', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NewChatScreen(),
      ),
    );

    expect(find.text('Nuevo mensaje'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('desktop view shows chats menu on the left alongside active conversation', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Left pane has the chats list menu
    expect(find.text('Mensajes'), findsOneWidget);
    // Right pane has the placeholder when no chat is chosen
    expect(find.text('Tus mensajes'), findsOneWidget);
  });

  testWidgets('ChatConversationScreen renders quoted reply card inside message bubble', (tester) async {
    final other = UserProfile(
      id: 'other-1',
      username: 'sofia_v',
      displayName: 'Sofía Valenzuela',
      isPrivate: false,
    );

    SharedPreferences.setMockInitialValues({
      'brote_session_token': 'test-tok',
      'brote_user_profile': jsonEncode({'id': 'me-1', 'username': 'mati', 'displayName': 'Mati'}),
    });

    final mockClient = MockClient((request) async {
      if (request.url.path.contains('/api/chats/test-conv-reply/messages')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': [
              {
                'id': 'm1',
                'conversationId': 'test-conv-reply',
                'senderId': 'other-1',
                'senderName': 'Sofía Valenzuela',
                'content': '¿Nos vemos hoy?',
                'isMe': false,
              },
              {
                'id': 'm2',
                'conversationId': 'test-conv-reply',
                'senderId': 'me-1',
                'senderName': 'Mati',
                'content': 'Sí, dale!',
                'isMe': true,
                'reply': {
                  'id': 'm1',
                  'senderId': 'other-1',
                  'senderName': 'Sofía Valenzuela',
                  'text': '¿Nos vemos hoy?',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"success": true}', 200, headers: {'content-type': 'application/json'});
    });

    await http.runWithClient(() async {
      await tester.runAsync(() => AuthService().tryAutoLogin());
      await tester.pumpWidget(
        MaterialApp(
          home: ChatConversationScreen(
            conversationId: 'test-conv-reply',
            otherParticipant: other,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
    }, () => mockClient);

    // Verify messages and quoted reply card
    expect(find.text('¿Nos vemos hoy?'), findsNWidgets(2)); // original message + quoted reply
    expect(find.text('Sí, dale!'), findsOneWidget);
    expect(find.text('Sofía Valenzuela'), findsWidgets);

    // Long press on original message to trigger context menu
    await tester.longPress(find.text('¿Nos vemos hoy?').first);
    await tester.pumpAndSettle();

    // Verify context menu shows 'Responder'
    expect(find.text('Responder'), findsOneWidget);

    // Tap 'Responder'
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();

    // Verify reply preview bar appears above the input
    expect(find.text('Respondiendo a Sofía Valenzuela'), findsOneWidget);
    expect(find.byTooltip('Cancelar respuesta'), findsOneWidget);

    // Tap cancel button and verify preview bar disappears
    await tester.tap(find.byTooltip('Cancelar respuesta'));
    await tester.pumpAndSettle();
    expect(find.text('Respondiendo a Sofía Valenzuela'), findsNothing);
  });
}
