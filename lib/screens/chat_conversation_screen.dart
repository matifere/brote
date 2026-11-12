import 'dart:async';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/chat_crypto.dart';
import '../services/message_notification_service.dart';
import '../widgets/chat_password_dialog.dart';
import '../widgets/chats_sidebar.dart';
import '../widgets/full_screen_image_viewer.dart';
import 'profile_screen.dart';

class ChatConversationScreen extends StatefulWidget {
  final String conversationId;
  final UserProfile otherParticipant;
  final bool isEmbedded;

  const ChatConversationScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipant,
    this.isEmbedded = false,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  late String _activeConversationId;
  late UserProfile _activeOtherParticipant;
  List<ChatMessage> _messages = [];
  late UserProfile _otherParticipant;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isPolling = false;
  Timer? _pollingTimer;

  /// Key shared with the other person; null while the chat isn't encrypted.
  SecretKey? _conversationKey;
  bool _isCryptoBusy = false;
  final Map<String, SecureChatPayload> _decrypted = {};
  final Set<String> _undecryptable = {};
  final Map<String, Future<Uint8List?>> _secureImages = {};

  @override
  void initState() {
    super.initState();
    _activeConversationId = widget.conversationId;
    _activeOtherParticipant = widget.otherParticipant;
    _otherParticipant = widget.otherParticipant;
    MessageNotificationService().activeConversationId = widget.conversationId;
    ChatCrypto().status.addListener(_onCryptoStatusChanged);
    _loadMessages();
    _prepareEncryption();

    // Poll for new messages every 3.5 seconds while open
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      _pollNewMessages();
    });
  }

  @override
  void didUpdateWidget(ChatConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _activeConversationId = widget.conversationId;
      _activeOtherParticipant = widget.otherParticipant;
      _otherParticipant = widget.otherParticipant;
      MessageNotificationService().activeConversationId = widget.conversationId;
      _messages.clear();
      _isLoading = true;
      _conversationKey = null;
      _decrypted.clear();
      _loadMessages();
      _prepareEncryption();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (MessageNotificationService().activeConversationId == widget.conversationId) {
      MessageNotificationService().activeConversationId = null;
    }
    ChatCrypto().status.removeListener(_onCryptoStatusChanged);
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final res = await AuthService().getConversationMessages(widget.conversationId);
    if (!mounted) return;

    if (res != null) {
      setState(() {
        _messages = res['messages'] as List<ChatMessage>;
        if (res['otherParticipant'] != null) {
          _otherParticipant = res['otherParticipant'] as UserProfile;
        }
        _isLoading = false;
      });
      _scrollToBottom();
      _decryptMessages();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pollNewMessages() async {
    // Skip this tick if the previous request is still in flight (slow network).
    if (_isPolling || _isLoading) return;
    _isPolling = true;
    try {
      final res = await AuthService().getConversationMessages(widget.conversationId);
      if (!mounted || res == null) return;

      final newMsgs = res['messages'] as List<ChatMessage>;
      final lastId = newMsgs.isNotEmpty ? newMsgs.last.id : null;
      final currentLastId = _messages.isNotEmpty ? _messages.last.id : null;
      if (newMsgs.length != _messages.length || lastId != currentLastId) {
        setState(() {
          _messages = newMsgs;
        });
        _scrollToBottom();
      }
      // The other person may have turned on encryption since the chat was opened
      if (_conversationKey == null && ChatCrypto().status.value == ChatCryptoStatus.ready) {
        await _loadConversationKey();
      } else {
        await _decryptMessages();
      }
    } finally {
      _isPolling = false;
    }
  }

  void _onCryptoStatusChanged() {
    if (mounted) setState(() {});
  }

  /// Loads this device's chat key and the key shared with the other person.
  Future<void> _prepareEncryption() async {
    await ChatCrypto().refresh();
    await _loadConversationKey();
  }

  Future<void> _loadConversationKey() async {
    final key = await ChatCrypto().keyForConversation(widget.conversationId, _otherParticipant.id);
    if (!mounted) return;
    setState(() {
      _conversationKey = key;
      _undecryptable.clear();
    });
    await _decryptMessages();
  }

  /// Decrypts messages that haven't been read yet; plaintext is cached by message id.
  Future<void> _decryptMessages() async {
    final key = _conversationKey;
    if (key == null) return;
    var changed = false;
    for (final msg in List.of(_messages)) {
      if (!ChatCipher.isEncrypted(msg.content) ||
          _decrypted.containsKey(msg.id) ||
          _undecryptable.contains(msg.id)) {
        continue;
      }
      final payload = await ChatCipher.decryptPayload(msg.content, key);
      if (payload != null) {
        _decrypted[msg.id] = payload;
      } else {
        _undecryptable.add(msg.id);
      }
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _unlockEncryption() async {
    final result = await showChatPasswordDialog(context, mode: ChatPasswordMode.unlock);
    if (result == null || !mounted) return;

    if (result.forgotPassword) {
      final reset = await showChatPasswordDialog(context, mode: ChatPasswordMode.reset);
      if (reset?.password == null || !mounted) return;
      await _runCryptoAction(() => ChatCrypto().createKeys(reset!.password!));
      return;
    }
    await _runCryptoAction(() => ChatCrypto().unlock(result.password!));
  }

  /// Runs a key operation (which can take a couple of seconds). Success shows in
  /// the encryption banner; only errors get a snackbar, which would cover the input.
  Future<void> _runCryptoAction(Future<String?> Function() action) async {
    setState(() => _isCryptoBusy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _isCryptoBusy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    await _loadConversationKey();
  }

  /// The chat upload endpoint returns a server-relative path
  /// (`/api/posts/media/...`), which Image.network cannot load on its own.
  String _resolveMediaUrl(String url) {
    if (url.startsWith('/')) return '${AuthService.neonServerUrl}$url';
    return url;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage({String? mediaUrl, SecureChatImage? secureImage}) async {
    if (_isSending) return;
    final text = _messageController.text.trim();
    if (text.isEmpty && mediaUrl == null && secureImage == null) return;

    _messageController.clear();
    setState(() => _isSending = true);

    // Ensure conversation key is ready; messages are strictly end-to-end encrypted
    var key = _conversationKey;
    if (key == null) {
      key = await ChatCrypto().keyForConversation(widget.conversationId, _otherParticipant.id);
      if (key != null) _conversationKey = key;
    }

    if (key == null) {
      _messageController.text = text;
      setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estableciendo conexión cifrada... Reintentá en un instante.')),
        );
      }
      return;
    }

    final payload = SecureChatPayload(text: text, image: secureImage);
    final content = await ChatCipher.encryptPayload(payload, key);

    final res = await AuthService().sendMessage(
      widget.conversationId,
      content: content,
      mediaUrl: mediaUrl,
    );

    if (!mounted) return;
    setState(() => _isSending = false);
    // Keep the cursor in the input so the next message can be typed right away.
    _inputFocusNode.requestFocus();

    if (res['success'] == true && res['message'] != null) {
      final sent = res['message'] as ChatMessage;
      _decrypted[sent.id] = payload;
      setState(() {
        // A poll may have already picked this message up while the send was in flight.
        if (!_messages.any((m) => m.id == sent.id)) {
          _messages.add(sent);
        }
      });
      _scrollToBottom();
    } else {
      // Give the unsent text back so the user doesn't lose it.
      if (text.isNotEmpty && _messageController.text.isEmpty) {
        _messageController.text = text;
      }
      final error = res['error'] as String? ?? 'Error al enviar el mensaje';
      final isPrivate = res['isPrivateRestricted'] as bool? ?? false;

      if (isPrivate) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.lock_rounded, size: 36, color: Theme.of(context).colorScheme.error),
            title: const Text('Acceso denegado'),
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Subiendo imagen...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );

        // Photos are always end-to-end encrypted before upload
        final (uploadBytes, imageKey) = await ChatCipher.encryptImage(bytes);
        final imageUrl = await AuthService().uploadChatImage(
          uploadBytes,
          filename: 'foto.enc',
        );

        if (imageUrl != null) {
          _secureImages[imageUrl] = Future.value(bytes);
          await _handleSendMessage(secureImage: SecureChatImage(url: imageUrl, key: imageKey));
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error al subir la imagen adjunta')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo seleccionar la foto: $e')),
        );
      }
    }
  }

  void _showMediaPickerSheet() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Elegir de la galería'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded),
                  title: const Text('Tomar foto con la cámara'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const double _thumbnailMaxWidth = 220;
  static const double _thumbnailMaxHeight = 280;

  /// Small preview inside the bubble, decoded at thumbnail size; tapping it
  /// opens the full-resolution photo.
  Widget _buildMediaThumbnail(ChatMessage msg, bool isMe, ColorScheme colorScheme) {
    final url = _resolveMediaUrl(msg.mediaUrl!);
    final heroTag = 'chat-media-${msg.id}';
    final cacheWidth =
        (_thumbnailMaxWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholderColor = isMe
        ? colorScheme.onPrimary.withValues(alpha: 0.15)
        : colorScheme.onSurface.withValues(alpha: 0.08);

    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        onTap: () => openFullScreenImage(
          context,
          imageUrl: url,
          heroTag: heroTag,
          thumbnailCacheWidth: cacheWidth,
          title: msg.isMe ? 'Vos' : msg.senderName,
          subtitle: msg.timeFormatted.isEmpty ? null : msg.timeFormatted,
        ),
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _thumbnailMaxWidth,
                maxHeight: _thumbnailMaxHeight,
              ),
              child: Image.network(
                url,
                cacheWidth: cacheWidth,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 180,
                    height: 180,
                    color: placeholderColor,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 140,
                  height: 100,
                  color: placeholderColor,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_rounded),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List?> _secureImageBytes(SecureChatImage image) {
    return _secureImages.putIfAbsent(image.url, () async {
      try {
        final response = await http.get(Uri.parse(_resolveMediaUrl(image.url))).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return null;
        return await ChatCipher.decryptImage(response.bodyBytes, image.key);
      } catch (e) {
        debugPrint('Error loading encrypted photo: $e');
        return null;
      }
    });
  }

  /// Like [_buildMediaThumbnail], for photos that are downloaded and decrypted on the device.
  Widget _buildSecureThumbnail(ChatMessage msg, SecureChatImage image, bool isMe, ColorScheme colorScheme) {
    final heroTag = 'chat-media-${msg.id}';
    final cacheWidth = (_thumbnailMaxWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholderColor = isMe
        ? colorScheme.onPrimary.withValues(alpha: 0.15)
        : colorScheme.onSurface.withValues(alpha: 0.08);

    return FutureBuilder<Uint8List?>(
      future: _secureImageBytes(image),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            width: 180,
            height: 180,
            color: placeholderColor,
            alignment: Alignment.center,
            child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return Container(
            width: 140,
            height: 100,
            color: placeholderColor,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_rounded),
          );
        }
        return MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          child: GestureDetector(
            onTap: () => openFullScreenImage(
              context,
              image: MemoryImage(bytes),
              heroTag: heroTag,
              thumbnailCacheWidth: cacheWidth,
              title: msg.isMe ? 'Vos' : msg.senderName,
              subtitle: msg.timeFormatted.isEmpty ? null : msg.timeFormatted,
            ),
            child: Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _thumbnailMaxWidth,
                    maxHeight: _thumbnailMaxHeight,
                  ),
                  child: Image.memory(bytes, cacheWidth: cacheWidth, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEncryptionBanner(ColorScheme colorScheme, TextTheme textTheme) {
    final status = ChatCrypto().status.value;
    if (status == ChatCryptoStatus.checking) return const SizedBox.shrink();

    final username = _otherParticipant.username;
    final isEncrypted = _conversationKey != null;
    final (IconData icon, String message, String? actionLabel, VoidCallback? action) = switch (status) {
      ChatCryptoStatus.locked => (
          Icons.lock_outline_rounded,
          'Ingresá la contraseña de tu cuenta para leer y enviar mensajes cifrados.',
          'Desbloquear',
          _unlockEncryption,
        ),
      ChatCryptoStatus.ready => (
          Icons.lock_rounded,
          'Cifrado de punta a punta: solo vos y @$username pueden leer estos mensajes y fotos.',
          null,
          null,
        ),
      _ => (
          Icons.lock_open_rounded,
          'Este chat no está cifrado: el servidor todavía no tiene el cifrado de punta a punta.',
          null,
          null,
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isEncrypted
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isEncrypted ? colorScheme.primary : colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          if (_isCryptoBusy)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (actionLabel != null)
            TextButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    );
  }

  void _openParticipantProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(profile: _otherParticipant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.sizeOf(context);
    final isDesktop = media.width >= 720 && media.width > media.height;

    // Desktop Standalone Mode: Display split screen with all available chats on the left
    if (isDesktop && !widget.isEmbedded) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border.symmetric(
                vertical: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 320,
                  child: ChatsSidebar(
                    headerLeading: Navigator.of(context).canPop()
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            tooltip: 'Volver',
                            onPressed: () => Navigator.of(context).pop(),
                          )
                        : null,
                    selectedConversationId: _activeConversationId,
                    onSelectChat: (chat) {
                      if (chat.id == _activeConversationId) return;
                      setState(() {
                        _activeConversationId = chat.id;
                        _activeOtherParticipant = chat.otherParticipant ??
                            UserProfile(
                              id: chat.id,
                              username: chat.username,
                              displayName: chat.displayName,
                              avatarUrl: chat.avatarUrl,
                            );
                      });
                    },
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
                Expanded(
                  child: ChatConversationScreen(
                    key: ValueKey(_activeConversationId),
                    conversationId: _activeConversationId,
                    otherParticipant: _activeOtherParticipant,
                    isEmbedded: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final displayName = _otherParticipant.displayName;
    final username = _otherParticipant.username;
    final avatarUrl = _otherParticipant.avatarUrl;
    final isPrivate = _otherParticipant.isPrivate;

    final conversationBody = Column(
      children: [
        _buildEncryptionBanner(colorScheme, textTheme),

        // Messages stream
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 48, color: colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              'Iniciá la conversación',
                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Enviá un mensaje para chatear con @$username.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.isMe;
                        final isEncrypted = ChatCipher.isEncrypted(msg.content);
                        final payload = _decrypted[msg.id];
                        final text = isEncrypted ? (payload?.text ?? '') : msg.content;
                        final secureImage = payload?.image;
                        final hasMedia =
                            (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) || secureImage != null;
                        final textColor = isMe ? colorScheme.onPrimary : colorScheme.onSurface;

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            constraints: BoxConstraints(
                              maxWidth: (MediaQuery.of(context).size.width * 0.76).clamp(200.0, 480.0),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? colorScheme.primary
                                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                // Optional Media Image
                                if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty)
                                  _buildMediaThumbnail(msg, isMe, colorScheme),
                                if (secureImage != null)
                                  _buildSecureThumbnail(msg, secureImage, isMe, colorScheme),
                                if (hasMedia && text.isNotEmpty) const SizedBox(height: 8),

                                // Encrypted message this device can't read (locked or old keys)
                                if (isEncrypted && payload == null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_outline_rounded,
                                          size: 14, color: textColor.withValues(alpha: 0.8)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Mensaje cifrado',
                                        style: TextStyle(
                                          color: textColor.withValues(alpha: 0.8),
                                          fontSize: 14.5,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),

                                // Text content
                                if (text.isNotEmpty)
                                  Text(
                                    text,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 14.5,
                                      height: 1.35,
                                    ),
                                  ),
                                const SizedBox(height: 4),

                                // Timestamp
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isEncrypted) ...[
                                      Icon(
                                        Icons.lock_rounded,
                                        size: 10,
                                        color: isMe
                                            ? colorScheme.onPrimary.withValues(alpha: 0.75)
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 3),
                                    ],
                                    Text(
                                      msg.timeFormatted,
                                      style: TextStyle(
                                        color: isMe
                                            ? colorScheme.onPrimary.withValues(alpha: 0.75)
                                            : colorScheme.onSurfaceVariant,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),

        // Message input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.add_photo_alternate_outlined, color: colorScheme.primary),
                  tooltip: 'Enviar foto',
                  onPressed: _showMediaPickerSheet,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _inputFocusNode,
                    maxLines: 4,
                    minLines: 1,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.send,
                    onEditingComplete: () {},
                    decoration: InputDecoration(
                      hintText: 'Escribí un mensaje...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      fillColor: colorScheme.surface,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _handleSendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  icon: _isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  onPressed: _isSending ? null : () => _handleSendMessage(),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          automaticallyImplyLeading: !widget.isEmbedded,
          titleSpacing: widget.isEmbedded ? 16 : 0,
          backgroundColor: colorScheme.surface,
          scrolledUnderElevation: 0,
          title: InkWell(
            onTap: _openParticipantProfile,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? NetworkImage(avatarUrl)
                        : null,
                    onBackgroundImageError: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? (exception, stackTrace) {}
                        : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_otherParticipant.isVerified) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.verified_rounded, size: 14, color: colorScheme.primary),
                            ],
                            if (isPrivate) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.lock_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                            ],
                          ],
                        ),
                        Text(
                          '@$username',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: widget.isEmbedded
          ? conversationBody
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: isDesktop
                      ? Border.symmetric(
                          vertical: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        )
                      : null,
                ),
                child: conversationBody,
              ),
            ),
    );
  }
}
