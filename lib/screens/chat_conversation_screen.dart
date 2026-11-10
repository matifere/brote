import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';

class ChatConversationScreen extends StatefulWidget {
  final String conversationId;
  final UserProfile otherParticipant;

  const ChatConversationScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipant,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  List<ChatMessage> _messages = [];
  late UserProfile _otherParticipant;
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _otherParticipant = widget.otherParticipant;
    _loadMessages();

    // Poll for new messages every 3.5 seconds while open
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      _pollNewMessages();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
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
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pollNewMessages() async {
    final res = await AuthService().getConversationMessages(widget.conversationId);
    if (!mounted || res == null) return;

    final newMsgs = res['messages'] as List<ChatMessage>;
    if (newMsgs.length != _messages.length) {
      setState(() {
        _messages = newMsgs;
      });
      _scrollToBottom();
    }
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

  Future<void> _handleSendMessage({String? mediaUrl}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && mediaUrl == null) return;

    _messageController.clear();
    setState(() => _isSending = true);

    final res = await AuthService().sendMessage(
      widget.conversationId,
      content: text.isNotEmpty ? text : null,
      mediaUrl: mediaUrl,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (res['success'] == true && res['message'] != null) {
      setState(() {
        _messages.add(res['message'] as ChatMessage);
      });
      _scrollToBottom();
    } else {
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

        final imageUrl = await AuthService().uploadChatImage(
          bytes,
          filename: picked.name,
        );

        if (imageUrl != null) {
          await _handleSendMessage(mediaUrl: imageUrl);
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

    final displayName = _otherParticipant.displayName;
    final username = _otherParticipant.username;
    final avatarUrl = _otherParticipant.avatarUrl;
    final isPrivate = _otherParticipant.isPrivate;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
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
      body: Column(
        children: [
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

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.76,
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
                                  if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        msg.mediaUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(Icons.broken_image_rounded),
                                      ),
                                    ),
                                    if (msg.content.isNotEmpty) const SizedBox(height: 8),
                                  ],

                                  // Text content
                                  if (msg.content.isNotEmpty)
                                    Text(
                                      msg.content,
                                      style: TextStyle(
                                        color: isMe ? colorScheme.onPrimary : colorScheme.onSurface,
                                        fontSize: 14.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  const SizedBox(height: 4),

                                  // Timestamp & checkmark
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        msg.timeFormatted,
                                        style: TextStyle(
                                          color: isMe
                                              ? colorScheme.onPrimary.withValues(alpha: 0.75)
                                              : colorScheme.onSurfaceVariant,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.done_all_rounded,
                                          size: 13,
                                          color: colorScheme.onPrimary.withValues(alpha: 0.8),
                                        ),
                                      ],
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
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
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
      ),
    );
  }
}
