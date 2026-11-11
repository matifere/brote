import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/main.dart';
import 'package:brote/models/chat_item.dart';
import 'package:brote/models/post_item.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/chat_conversation_screen.dart';
import 'package:brote/screens/main_navigation_screen.dart';
import 'package:brote/services/auth_service.dart';

void main() {
  test('PostItem parses isFollowingAuthor used by the Siguiendo tab', () {
    final followed = PostItem.fromJson({
      'id': 'p1',
      'authorId': 'a1',
      'content': 'hola',
      'isFollowingAuthor': true,
    });
    final notFollowed = PostItem.fromJson({
      'id': 'p2',
      'authorId': 'a2',
      'content': 'chau',
    });

    expect(followed.isFollowingAuthor, isTrue);
    expect(notFollowed.isFollowingAuthor, isFalse);
  });

  test('ChatItem.timeFormatted shows minutes elapsed, not minute of the hour', () {
    final chat = ChatItem(
      id: 'c1',
      lastMessage: 'hola',
      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 5, seconds: 10)),
    );

    expect(chat.timeFormatted, '5 m');
  });

  testWidgets('Chat input keeps focus after sending and keeps unsent text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().logout();

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatConversationScreen(
          conversationId: 'conv-1',
          otherParticipant: UserProfile(id: 'other-1', username: 'sofia_v', displayName: 'Sofía'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'hola');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    // There's no session, so the send fails and the text is handed back.
    expect(find.text('hola'), findsOneWidget);
  });

  testWidgets('AuthGate returns to login when the restored session is cleared', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({
      'brote_session_token': 'mock-token',
      'brote_user_profile': jsonEncode({
        'id': 'test-uuid-002',
        'username': 'expirado',
        'displayName': 'Sesión Vencida',
      }),
    });

    await tester.pumpWidget(const BroteApp());
    await tester.pumpAndSettle();
    expect(find.byType(MainNavigationScreen), findsOneWidget);

    // Simulates the background token check finding an expired session.
    await AuthService().logout();
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScreen), findsNothing);
    expect(find.text('Iniciar Sesión'), findsOneWidget);
  });
}
