import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/chat_message.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/chat_conversation_screen.dart';
import 'package:brote/services/auth_service.dart';
import 'package:brote/services/giphy_service.dart';
import 'package:brote/widgets/giphy_picker_sheet.dart';

void main() {
  group('GiphyService', () {
    test('parses trending and search responses correctly', () async {
      final fakeJson = {
        'data': [
          {
            'id': 'gif-1',
            'title': 'Excited Dance',
            'images': {
              'fixed_height': {
                'url': 'https://media.giphy.com/media/gif-1/200.gif',
                'width': '200',
                'height': '200',
              },
              'original': {
                'url': 'https://media.giphy.com/media/gif-1/giphy.gif',
              },
            },
          },
        ],
      };

      final client = MockClient((request) async {
        return http.Response(jsonEncode(fakeJson), 200, headers: {'content-type': 'application/json'});
      });

      final service = GiphyService(apiKey: 'fake-key', client: client);

      final trending = await service.getTrending();
      expect(trending.length, 1);
      expect(trending.first.id, 'gif-1');
      expect(trending.first.title, 'Excited Dance');
      expect(trending.first.previewUrl, 'https://media.giphy.com/media/gif-1/200.gif');
      expect(trending.first.originalUrl, 'https://media.giphy.com/media/gif-1/giphy.gif');

      final search = await service.search('dance');
      expect(search.length, 1);
      expect(search.first.title, 'Excited Dance');
    });

    test('returns empty list gracefully on HTTP error', () async {
      final client = MockClient((request) async {
        return http.Response('Server error', 500);
      });

      final service = GiphyService(apiKey: 'fake-key', client: client);
      final results = await service.getTrending();
      expect(results, isEmpty);
    });
  });

  group('GiphyPickerSheet Widget', () {
    testWidgets('renders Giphy header, search bar, and selects a GIF', (tester) async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'g1',
                'title': 'Party Cat',
                'images': {
                  'fixed_height': {'url': 'https://media.giphy.com/media/g1/200.gif'},
                  'original': {'url': 'https://media.giphy.com/media/g1/giphy.gif'},
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = GiphyService(apiKey: 'fake-key', client: client);

      String? selectedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedUrl = await showModalBottomSheet<String>(
                    context: context,
                    builder: (ctx) => GiphyPickerSheet(service: service),
                  );
                },
                child: const Text('Abrir GIFs'),
              ),
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Abrir GIFs'));
      await tester.pumpAndSettle();

      // Verify header & search bar
      expect(find.text('GIFs'), findsOneWidget);
      expect(find.text('Powered by GIPHY'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      // Tap on the GIF to select it
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      // Verify the sheet closed and returned the original URL
      expect(find.text('Powered by GIPHY'), findsNothing);
      expect(selectedUrl, 'https://media.giphy.com/media/g1/giphy.gif');
    });
  });

  group('ChatConversationScreen GIF UI', () {
    testWidgets('renders GIF button in input bar and displays GIF badge in bubble', (tester) async {
      SharedPreferences.setMockInitialValues({
        'brote_session_token': 'test-tok',
        'brote_user_profile': jsonEncode({'id': 'me-1', 'username': 'mati', 'displayName': 'Mati'}),
      });

      final other = UserProfile(
        id: 'user-2',
        username: 'martin',
        displayName: 'Martín',
        isPrivate: false,
      );

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/chats/conv-gif/messages')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': [
                {
                  'id': 'msg-gif-1',
                  'conversationId': 'conv-gif',
                  'senderId': 'user-2',
                  'senderName': 'Martín',
                  'content': 'Mirá esto',
                  'mediaUrl': 'https://media.giphy.com/media/test/giphy.gif',
                  'isMe': false,
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
              conversationId: 'conv-gif',
              otherParticipant: other,
            ),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }, () => mockClient);

      // Verify GIF button in the input bar
      expect(find.byIcon(Icons.gif_box_outlined), findsOneWidget);
      expect(find.byTooltip('Buscar GIF (GIPHY)'), findsOneWidget);

      // Verify GIF bubble renders image and GIF badge
      expect(find.text('GIF'), findsOneWidget);
      expect(find.text('Mirá esto'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    test('ChatMessage isGif helper recognizes GIF URLs', () {
      final gifMsg = ChatMessage(
        id: '1',
        conversationId: 'c1',
        senderId: 'u1',
        senderName: 'U',
        senderUsername: 'u',
        content: '',
        mediaUrl: 'https://media.giphy.com/media/xyz/giphy.gif',
        isMe: true,
      );
      expect(gifMsg.isGif, isTrue);

      final photoMsg = ChatMessage(
        id: '2',
        conversationId: 'c1',
        senderId: 'u1',
        senderName: 'U',
        senderUsername: 'u',
        content: '',
        mediaUrl: 'https://storage.neon.tech/foto.jpg',
        isMe: true,
      );
      expect(photoMsg.isGif, isFalse);
    });
  });
}
