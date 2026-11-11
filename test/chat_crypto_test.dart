import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:brote/services/chat_crypto.dart';

void main() {
  group('ChatCipher', () {
    test('both participants derive the same conversation key', () async {
      final ana = await ChatCipher.newKeyPair();
      final beto = await ChatCipher.newKeyPair();

      final anaKey = await ChatCipher.conversationKey(
        myKeyPair: ana,
        theirPublicKey: (await beto.extractPublicKey()).bytes,
        conversationId: 'conv-1',
      );
      final betoKey = await ChatCipher.conversationKey(
        myKeyPair: beto,
        theirPublicKey: (await ana.extractPublicKey()).bytes,
        conversationId: 'conv-1',
      );

      final content = await ChatCipher.encryptPayload(const SecureChatPayload(text: 'Hola Beto'), anaKey);
      expect(content, startsWith(ChatCipher.prefix));
      expect(content.contains('Hola'), isFalse);

      final decrypted = await ChatCipher.decryptPayload(content, betoKey);
      expect(decrypted?.text, 'Hola Beto');
      expect(decrypted?.preview, 'Hola Beto');
    });

    test('a key from another conversation or person cannot decrypt', () async {
      final ana = await ChatCipher.newKeyPair();
      final beto = await ChatCipher.newKeyPair();
      final carla = await ChatCipher.newKeyPair();
      final betoPublic = (await beto.extractPublicKey()).bytes;

      final key = await ChatCipher.conversationKey(myKeyPair: ana, theirPublicKey: betoPublic, conversationId: 'conv-1');
      final otherConversation =
          await ChatCipher.conversationKey(myKeyPair: ana, theirPublicKey: betoPublic, conversationId: 'conv-2');
      final eavesdropper = await ChatCipher.conversationKey(
        myKeyPair: carla,
        theirPublicKey: betoPublic,
        conversationId: 'conv-1',
      );

      final content = await ChatCipher.encryptPayload(const SecureChatPayload(text: 'secreto'), key);
      expect(await ChatCipher.decryptPayload(content, otherConversation), isNull);
      expect(await ChatCipher.decryptPayload(content, eavesdropper), isNull);
    });

    test('tampered messages are rejected and plain messages are left alone', () async {
      final ana = await ChatCipher.newKeyPair();
      final beto = await ChatCipher.newKeyPair();
      final key = await ChatCipher.conversationKey(
        myKeyPair: ana,
        theirPublicKey: (await beto.extractPublicKey()).bytes,
        conversationId: 'conv-1',
      );

      final content = await ChatCipher.encryptPayload(const SecureChatPayload(text: 'pagame 100'), key);
      final bytes = base64Decode(content.substring(ChatCipher.prefix.length));
      bytes[bytes.length - 20] ^= 0x01;
      final tampered = '${ChatCipher.prefix}${base64Encode(bytes)}';

      expect(await ChatCipher.decryptPayload(tampered, key), isNull);
      expect(await ChatCipher.decryptPayload('hola sin cifrar', key), isNull);
      expect(ChatCipher.isEncrypted('hola sin cifrar'), isFalse);
    });

    test('photos are encrypted with their own key carried in the message', () async {
      final photo = List<int>.generate(2048, (i) => i % 251);
      final (encrypted, imageKey) = await ChatCipher.encryptImage(photo);
      expect(encrypted.length, greaterThan(photo.length));
      expect(await ChatCipher.decryptImage(encrypted, imageKey), photo);

      final (_, otherKey) = await ChatCipher.encryptImage([1, 2, 3]);
      expect(await ChatCipher.decryptImage(encrypted, otherKey), isNull);

      const payload = SecureChatPayload(image: SecureChatImage(url: 'https://x/y', key: 'k'));
      final roundTrip = SecureChatPayload.fromJson(jsonDecode(jsonEncode(payload.toJson())) as Map<String, dynamic>);
      expect(roundTrip.image?.url, 'https://x/y');
      expect(roundTrip.preview, '📷 Foto');
    });

    test('the password backup restores the same key pair', () async {
      final keyPair = await ChatCipher.newKeyPair();
      final bundle = await ChatCipher.wrapKeyPair(keyPair, 'una contraseña larga', iterations: 1000);

      final stored = ChatKeyBundle.fromJson(jsonDecode(jsonEncode(bundle.toJson())) as Map<String, dynamic>);
      final restored = await ChatCipher.unwrapKeyPair(stored, 'una contraseña larga');
      expect(restored, isNotNull);
      expect((await restored!.extractPublicKey()).bytes, (await keyPair.extractPublicKey()).bytes);

      // Raw private bytes may differ by X25519 clamping (browsers), so check it reads the same messages
      final friend = await ChatCipher.newKeyPair();
      final friendKey = await ChatCipher.conversationKey(
        myKeyPair: friend,
        theirPublicKey: (await keyPair.extractPublicKey()).bytes,
        conversationId: 'conv-1',
      );
      final restoredKey = await ChatCipher.conversationKey(
        myKeyPair: restored,
        theirPublicKey: (await friend.extractPublicKey()).bytes,
        conversationId: 'conv-1',
      );
      final content = await ChatCipher.encryptPayload(const SecureChatPayload(text: 'sigo acá'), friendKey);
      expect((await ChatCipher.decryptPayload(content, restoredKey))?.text, 'sigo acá');

      expect(await ChatCipher.unwrapKeyPair(stored, 'otra contraseña'), isNull);
      expect(stored.encryptedPrivateKey.contains(base64Encode(await keyPair.extractPrivateKeyBytes())), isFalse);
    });
  });
}
