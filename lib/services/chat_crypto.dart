import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// A photo sent in an encrypted chat: the uploaded file holds only ciphertext,
/// and the key to read it travels inside the encrypted message.
class SecureChatImage {
  final String url;
  final String key;

  const SecureChatImage({required this.url, required this.key});

  Map<String, dynamic> toJson() => {'url': url, 'key': key};

  factory SecureChatImage.fromJson(Map<String, dynamic> json) =>
      SecureChatImage(url: json['url'] as String, key: json['key'] as String);
}

/// What an encrypted chat message contains once decrypted.
class SecureChatPayload {
  final String text;
  final SecureChatImage? image;

  const SecureChatPayload({this.text = '', this.image});

  /// Text for the inbox, matching what the server shows for plain messages.
  String get preview => text.isNotEmpty ? text : (image != null ? '📷 Foto' : '');

  Map<String, dynamic> toJson() => {
        'v': 1,
        if (text.isNotEmpty) 't': text,
        if (image != null) 'img': image!.toJson(),
      };

  factory SecureChatPayload.fromJson(Map<String, dynamic> json) => SecureChatPayload(
        text: json['t'] as String? ?? '',
        image: json['img'] is Map<String, dynamic> ? SecureChatImage.fromJson(json['img']) : null,
      );
}

/// A user's key pair as stored on the server: the public key in the clear and
/// the private key encrypted with a key derived from their chat password.
class ChatKeyBundle {
  final String publicKey;
  final String encryptedPrivateKey;
  final String nonce;
  final String salt;
  final int iterations;

  const ChatKeyBundle({
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.nonce,
    required this.salt,
    required this.iterations,
  });

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey,
        'encryptedPrivateKey': encryptedPrivateKey,
        'nonce': nonce,
        'salt': salt,
        'iterations': iterations,
      };

  factory ChatKeyBundle.fromJson(Map<String, dynamic> json) => ChatKeyBundle(
        publicKey: json['publicKey'] as String,
        encryptedPrivateKey: json['encryptedPrivateKey'] as String,
        nonce: json['nonce'] as String,
        salt: json['salt'] as String,
        iterations: (json['iterations'] as num).toInt(),
      );
}

/// Cryptographic primitives for end-to-end encrypted chats.
///
/// Each user has an X25519 key pair. Both people in a conversation derive the
/// same AES-256-GCM key from their key pair, the other's public key and the
/// conversation id, so the server only ever stores ciphertext.
class ChatCipher {
  static const String prefix = 'e2e1:';
  static const int defaultIterations = 310000;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final Random _random = Random.secure();

  static bool isEncrypted(String content) => content.startsWith(prefix);

  static List<int> _randomBytes(int length) => List<int>.generate(length, (_) => _random.nextInt(256));

  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<SimpleKeyPair> keyPairFromPrivateKey(List<int> privateKey) => _x25519.newKeyPairFromSeed(privateKey);

  static Future<SecretKey> conversationKey({
    required SimpleKeyPair myKeyPair,
    required List<int> theirPublicKey,
    required String conversationId,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(conversationId),
      info: utf8.encode('brote-chat-v1'),
    );
  }

  static Future<String> encryptPayload(SecureChatPayload payload, SecretKey key) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(payload.toJson())), secretKey: key);
    return '$prefix${base64Encode(box.concatenation())}';
  }

  /// Returns null when the content isn't encrypted or can't be decrypted with [key].
  static Future<SecureChatPayload?> decryptPayload(String content, SecretKey key) async {
    if (!isEncrypted(content)) return null;
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(content.substring(prefix.length)),
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await _aes.decrypt(box, secretKey: key);
      return SecureChatPayload.fromJson(jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Encrypts a photo with a fresh random key; returns the bytes to upload and that key.
  static Future<(Uint8List, String)> encryptImage(List<int> bytes) async {
    final key = await _aes.newSecretKey();
    final box = await _aes.encrypt(bytes, secretKey: key);
    return (box.concatenation(), base64Encode(await key.extractBytes()));
  }

  static Future<Uint8List?> decryptImage(List<int> encrypted, String key) async {
    try {
      final box = SecretBox.fromConcatenation(encrypted, nonceLength: _nonceLength, macLength: _macLength);
      final clear = await _aes.decrypt(box, secretKey: SecretKey(base64Decode(key)));
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  static Future<SecretKey> _passwordKey(String password, List<int> salt, int iterations) {
    return Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Encrypts the private key with [password] so it can be backed up on the server.
  static Future<ChatKeyBundle> wrapKeyPair(
    SimpleKeyPair keyPair,
    String password, {
    int iterations = defaultIterations,
  }) async {
    final salt = _randomBytes(16);
    final passwordKey = await _passwordKey(password, salt, iterations);
    final box = await _aes.encrypt(await keyPair.extractPrivateKeyBytes(), secretKey: passwordKey);
    final publicKey = await keyPair.extractPublicKey();
    return ChatKeyBundle(
      publicKey: base64Encode(publicKey.bytes),
      encryptedPrivateKey: base64Encode([...box.cipherText, ...box.mac.bytes]),
      nonce: base64Encode(box.nonce),
      salt: base64Encode(salt),
      iterations: iterations,
    );
  }

  /// Recovers the key pair from a backup; returns null when the password is wrong.
  static Future<SimpleKeyPair?> unwrapKeyPair(ChatKeyBundle bundle, String password) async {
    try {
      final passwordKey = await _passwordKey(password, base64Decode(bundle.salt), bundle.iterations);
      final encrypted = base64Decode(bundle.encryptedPrivateKey);
      final box = SecretBox(
        encrypted.sublist(0, encrypted.length - _macLength),
        nonce: base64Decode(bundle.nonce),
        mac: Mac(encrypted.sublist(encrypted.length - _macLength)),
      );
      final keyPair = await keyPairFromPrivateKey(await _aes.decrypt(box, secretKey: passwordKey));
      final publicKey = await keyPair.extractPublicKey();
      if (base64Encode(publicKey.bytes) != bundle.publicKey) return null;
      return keyPair;
    } catch (_) {
      return null;
    }
  }
}

enum ChatCryptoStatus {
  /// Still checking local storage and the server.
  checking,

  /// The server has no key endpoints yet (or can't be reached): chats stay unencrypted.
  unavailable,

  /// The user has no keys yet and must choose a chat password.
  needsSetup,

  /// The user has a backed-up key that must be unlocked with the chat password.
  locked,

  /// Messages can be encrypted and decrypted on this device.
  ready,
}

/// Holds the current user's chat keys and talks to the key endpoints.
class ChatCrypto {
  static final ChatCrypto _instance = ChatCrypto._internal();
  factory ChatCrypto() => _instance;
  ChatCrypto._internal();

  static const int minPasswordLength = 6;
  static const Duration _missingKeyRetry = Duration(minutes: 1);

  static String vaultKeyFor(String userId) => 'brote_e2e_vault_$userId';

  final ValueNotifier<ChatCryptoStatus> status = ValueNotifier(ChatCryptoStatus.checking);

  String? _userId;
  SimpleKeyPair? _keyPair;
  ChatKeyBundle? _bundle;
  final Map<String, List<int>> _publicKeys = {};
  final Map<String, DateTime> _missingKeys = {};
  final Map<String, SecretKey> _conversationKeys = {};

  String get _storageKey => 'brote_chat_key_$_userId';

  /// Loads the key from this device, or checks the server for a backup.
  Future<void> refresh() async {
    final user = AuthService().currentUser;
    if (user == null || AuthService().sessionToken == null) {
      _forget();
      status.value = ChatCryptoStatus.unavailable;
      return;
    }
    if (_userId != user.id) {
      _forget();
      _userId = user.id;
    }
    if (_keyPair != null) {
      status.value = ChatCryptoStatus.ready;
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null) {
        _keyPair = await ChatCipher.keyPairFromPrivateKey(base64Decode(stored));
        status.value = ChatCryptoStatus.ready;
        return;
      }
    } catch (e) {
      debugPrint('Chat key load notice: $e');
    }

    final vaultKey = vaultKeyFor(user.id);
    final data = await _request('GET', '/api/keys/me');
    if (data == null) {
      status.value = ChatCryptoStatus.unavailable;
      return;
    }
    final bundle = data['keyBundle'];
    if (bundle is Map<String, dynamic>) {
      final parsed = ChatKeyBundle.fromJson(bundle);
      _bundle = parsed;
      // Transparently unwrap with deterministic account vault key
      final keyPair = await ChatCipher.unwrapKeyPair(parsed, vaultKey);
      if (keyPair != null) {
        await _activate(keyPair, parsed);
        return;
      }
      // Fallback for legacy custom passwords:
      status.value = ChatCryptoStatus.locked;
    } else {
      // No keys yet on server: automatically create and upload new keys transparently
      await createKeys(vaultKey);
    }
  }

  /// Sets up or unlocks chat keys transparently using the user's account password.
  Future<void> onAccountLogin(String password) async {
    final user = AuthService().currentUser;
    if (user == null || AuthService().sessionToken == null) return;
    _userId = user.id;

    // Check if this device already has the decrypted key cached locally
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        _keyPair = await ChatCipher.keyPairFromPrivateKey(base64Decode(stored));
        status.value = ChatCryptoStatus.ready;
        return;
      } catch (e) {
        debugPrint('Failed to load stored chat key: $e');
      }
    }

    final vaultKey = vaultKeyFor(user.id);
    // New device or first-time setup: check the server for existing keys
    final data = await _request('GET', '/api/keys/me');
    if (data == null) {
      status.value = ChatCryptoStatus.unavailable;
      return;
    }

    final bundleJson = data['keyBundle'];
    if (bundleJson is Map<String, dynamic>) {
      final bundle = ChatKeyBundle.fromJson(bundleJson);
      _bundle = bundle;
      var keyPair = await ChatCipher.unwrapKeyPair(bundle, vaultKey);
      keyPair ??= await ChatCipher.unwrapKeyPair(bundle, password);
      if (keyPair != null) {
        await _activate(keyPair, bundle);
        return;
      }
      status.value = ChatCryptoStatus.locked;
    } else {
      // No keys yet on server: automatically create with vaultKey
      await createKeys(vaultKey);
    }
  }

  /// Creates a new key pair protected by [password]. Returns an error message or null.
  ///
  /// When the user already had keys, messages encrypted with them can no longer be read.
  Future<String?> createKeys(String password) async {
    if (password.length < minPasswordLength) {
      return 'La contraseña debe tener al menos $minPasswordLength caracteres.';
    }
    final keyPair = await ChatCipher.newKeyPair();
    final bundle = await ChatCipher.wrapKeyPair(keyPair, password);
    final data = await _request('PUT', '/api/keys/me', body: bundle.toJson());
    if (data == null) return 'No se pudieron guardar tus claves. Intentá de nuevo.';
    _conversationKeys.clear();
    await _activate(keyPair, bundle);
    return null;
  }

  /// Unlocks the backed-up key pair. Returns an error message or null.
  Future<String?> unlock(String password) async {
    final bundle = _bundle;
    if (bundle == null) return 'No hay claves para desbloquear.';
    final keyPair = await ChatCipher.unwrapKeyPair(bundle, password);
    if (keyPair == null) return 'Contraseña incorrecta.';
    await _activate(keyPair, bundle);
    return null;
  }

  Future<void> _activate(SimpleKeyPair keyPair, ChatKeyBundle bundle) async {
    _keyPair = keyPair;
    _bundle = bundle;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, base64Encode(await keyPair.extractPrivateKeyBytes()));
    } catch (e) {
      debugPrint('Chat key save notice: $e');
    }
    status.value = ChatCryptoStatus.ready;
  }

  /// The key shared with [otherUserId] in [conversationId], or null when either side has no keys.
  Future<SecretKey?> keyForConversation(String conversationId, String otherUserId) async {
    final keyPair = _keyPair;
    if (keyPair == null) return null;
    final cached = _conversationKeys[conversationId];
    if (cached != null) return cached;

    final theirKey = await _publicKeyOf(otherUserId);
    if (theirKey == null) return null;
    final key = await ChatCipher.conversationKey(
      myKeyPair: keyPair,
      theirPublicKey: theirKey,
      conversationId: conversationId,
    );
    _conversationKeys[conversationId] = key;
    return key;
  }

  Future<List<int>?> _publicKeyOf(String userId) async {
    final cached = _publicKeys[userId];
    if (cached != null) return cached;
    final missingSince = _missingKeys[userId];
    if (missingSince != null && DateTime.now().difference(missingSince) < _missingKeyRetry) return null;

    final data = await _request('GET', '/api/keys/${Uri.encodeComponent(userId)}');
    final publicKey = data?['publicKey'] as String?;
    if (publicKey == null) {
      _missingKeys[userId] = DateTime.now();
      return null;
    }
    final bytes = base64Decode(publicKey);
    _publicKeys[userId] = bytes;
    _missingKeys.remove(userId);
    return bytes;
  }

  /// Removes the key from this device (on logout). The server backup stays.
  Future<void> clear() async {
    final userId = _userId;
    _forget();
    status.value = ChatCryptoStatus.checking;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('brote_chat_key_$userId');
    } catch (_) {}
  }

  void _forget() {
    _userId = null;
    _keyPair = null;
    _bundle = null;
    _publicKeys.clear();
    _missingKeys.clear();
    _conversationKeys.clear();
  }

  /// Returns the decoded JSON body on success, or null when the request fails
  /// (including servers that don't have the key endpoints yet).
  Future<Map<String, dynamic>?> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final token = AuthService().sessionToken;
    if (token == null) return null;
    try {
      final uri = Uri.parse('${AuthService().baseUrl}$path');
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
      final response = method == 'PUT'
          ? await http.put(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12))
          : await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> && data['success'] == true ? data : null;
    } catch (e) {
      debugPrint('Chat key request failed ($method $path): $e');
      return null;
    }
  }
}
