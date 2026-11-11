import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/chat_conversation_screen.dart';
import 'package:brote/services/auth_service.dart';
import 'package:brote/services/chat_crypto.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _password = 'clave-de-chat';
const _me = {'id': 'me-1', 'username': 'ana', 'displayName': 'Ana'};
const _other = UserProfile(id: 'other-1', username: 'beto', displayName: 'Beto');

void main() {
  late SimpleKeyPair otherKeys;
  late SecretKey otherConversationKey;
  late ChatKeyBundle myBundle;
  late String encryptedHello;

  setUpAll(() async {
    final myKeys = await ChatCipher.newKeyPair();
    otherKeys = await ChatCipher.newKeyPair();
    // Few iterations keep the test fast; the app uses ChatCipher.defaultIterations
    myBundle = await ChatCipher.wrapKeyPair(myKeys, _password, iterations: 1000);
    otherConversationKey = await ChatCipher.conversationKey(
      myKeyPair: otherKeys,
      theirPublicKey: (await myKeys.extractPublicKey()).bytes,
      conversationId: 'conv-1',
    );
    encryptedHello = await ChatCipher.encryptPayload(
      const SecureChatPayload(text: 'Hola, esto viaja cifrado'),
      otherConversationKey,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'brote_session_token': 'tok',
      'brote_user_profile': jsonEncode(_me),
    });
    await ChatCrypto().clear();
  });

  /// A fake API that only ever sees ciphertext; [sent] collects what the app posts.
  MockClient fakeServer({required bool hasKeyEndpoints, List<String>? sent}) {
    return MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/auth/me') {
        return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
      }
      if (path == '/api/chats/conv-1/messages' && request.method == 'GET') {
        return _json({
          'success': true,
          'messages': [
            {
              'id': 'm1',
              'conversationId': 'conv-1',
              'senderId': 'other-1',
              'senderName': 'Beto',
              'senderUsername': 'beto',
              'content': encryptedHello,
              'isMe': false,
            },
          ],
        });
      }
      if (path == '/api/chats/conv-1/messages' && request.method == 'POST') {
        final content = (jsonDecode(request.body) as Map<String, dynamic>)['content'] as String;
        sent?.add(content);
        return _json({
          'success': true,
          'message': {'id': 'm2', 'conversationId': 'conv-1', 'senderId': 'me-1', 'content': content, 'isMe': true},
        });
      }
      if (hasKeyEndpoints && path == '/api/keys/me') {
        return _json({'success': true, 'keyBundle': myBundle.toJson()});
      }
      if (hasKeyEndpoints && path == '/api/keys/other-1') {
        final publicKey = await otherKeys.extractPublicKey();
        return _json({'success': true, 'publicKey': base64Encode(publicKey.bytes)});
      }
      return http.Response('404 Not Found', 404);
    });
  }

  Future<void> openChat(WidgetTester tester, MockClient server) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await http.runWithClient(() async {
      await tester.runAsync(() => AuthService().tryAutoLogin());
      await tester.pumpWidget(
        const MaterialApp(home: ChatConversationScreen(conversationId: 'conv-1', otherParticipant: _other)),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
    }, () => server);
  }

  Future<void> closeChat(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await AuthService().logout();
  }

  testWidgets('without the key endpoints the chat says it is not encrypted', (tester) async {
    await openChat(tester, fakeServer(hasKeyEndpoints: false));

    expect(find.textContaining('el servidor todavía no tiene el cifrado'), findsOneWidget);
    expect(find.text('Mensaje cifrado'), findsOneWidget);
    expect(find.text('Hola, esto viaja cifrado'), findsNothing);

    await closeChat(tester);
  });

  testWidgets('unlocking with the chat password decrypts and encrypts messages', (tester) async {
    final sent = <String>[];
    final server = fakeServer(hasKeyEndpoints: true, sent: sent);
    await openChat(tester, server);

    expect(find.textContaining('Ingresá la contraseña de tu cuenta'), findsOneWidget);
    expect(find.text('Mensaje cifrado'), findsOneWidget);

    await http.runWithClient(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Desbloquear'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), _password);
      await tester.tap(find.widgetWithText(FilledButton, 'Desbloquear'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
    }, () => server);

    expect(find.text('Hola, esto viaja cifrado'), findsOneWidget);
    expect(find.text('Mensaje cifrado'), findsNothing);
    expect(find.textContaining('Cifrado de punta a punta'), findsOneWidget);

    await http.runWithClient(() async {
      await tester.enterText(find.byType(TextField), 'respuesta secreta');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }, () => server);

    // The server only got ciphertext, which the other person can read
    expect(sent, hasLength(1));
    expect(sent.single, startsWith(ChatCipher.prefix));
    expect(sent.single.contains('respuesta'), isFalse);
    final payload = await ChatCipher.decryptPayload(sent.single, otherConversationKey);
    expect(payload?.text, 'respuesta secreta');
    expect(find.text('respuesta secreta'), findsOneWidget);

    await closeChat(tester);
  });

  testWidgets('a wrong chat password keeps the chat locked', (tester) async {
    final server = fakeServer(hasKeyEndpoints: true);
    await openChat(tester, server);

    await http.runWithClient(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Desbloquear'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'otra-clave');
      await tester.tap(find.widgetWithText(FilledButton, 'Desbloquear'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
    }, () => server);

    expect(find.text('Contraseña incorrecta.'), findsOneWidget);
    expect(find.text('Mensaje cifrado'), findsOneWidget);
    expect(find.text('Hola, esto viaja cifrado'), findsNothing);

    await closeChat(tester);
  });

  testWidgets('logging in with account password unlocks chats automatically without any prompts', (tester) async {
    final server = fakeServer(hasKeyEndpoints: true);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await http.runWithClient(() async {
      // Simulate login on a new device where only account credentials are typed
      await AuthService().tryAutoLogin();
      await ChatCrypto().onAccountLogin(_password);
      await tester.pumpWidget(
        const MaterialApp(home: ChatConversationScreen(conversationId: 'conv-1', otherParticipant: _other)),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
    }, () => server);

    // Messages are immediately decrypted and no password prompt or unlock button is shown
    expect(find.text('Hola, esto viaja cifrado'), findsOneWidget);
    expect(find.text('Mensaje cifrado'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Desbloquear'), findsNothing);
    expect(find.textContaining('Cifrado de punta a punta'), findsOneWidget);

    await closeChat(tester);
  });

  testWidgets('entering a chat automatically initializes encryption with zero prompts or passwords', (tester) async {
    ChatKeyBundle? uploadedBundle;
    final server = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/auth/me') {
        return _json({'success': true, 'token': 'tok', 'user': _me, 'profile': _me});
      }
      if (path == '/api/chats/conv-1/messages') {
        return _json({'success': true, 'messages': []});
      }
      if (path == '/api/keys/me') {
        if (request.method == 'GET') {
          return _json({'success': true, 'keyBundle': uploadedBundle?.toJson()});
        }
        if (request.method == 'PUT') {
          uploadedBundle = ChatKeyBundle.fromJson(jsonDecode(request.body) as Map<String, dynamic>);
          return _json({'success': true});
        }
      }
      if (path == '/api/keys/other-1') {
        final publicKey = await otherKeys.extractPublicKey();
        return _json({'success': true, 'publicKey': base64Encode(publicKey.bytes)});
      }
      return http.Response('404 Not Found', 404);
    });

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await http.runWithClient(() async {
      await AuthService().tryAutoLogin();
      await tester.pumpWidget(
        const MaterialApp(home: ChatConversationScreen(conversationId: 'conv-1', otherParticipant: _other)),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }, () => server);

    // Completely automatic: encryption is active, bundle was created, zero password prompts
    expect(uploadedBundle, isNotNull);
    expect(find.textContaining('Cifrado de punta a punta'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextFormField), findsNothing);

    await closeChat(tester);
  });
}
