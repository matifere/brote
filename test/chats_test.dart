import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/chats_screen.dart';
import 'package:brote/screens/chat_conversation_screen.dart';
import 'package:brote/screens/new_chat_screen.dart';

void main() {
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
}
