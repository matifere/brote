import 'package:flutter/material.dart';
import 'chats_screen.dart';

class ChatMessage {
  final String text;
  final bool isMe;
  final String time;

  ChatMessage({required this.text, required this.isMe, required this.time});
}

class ChatConversationScreen extends StatefulWidget {
  final ChatItem chat;

  const ChatConversationScreen({super.key, required this.chat});

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _messages.addAll([
      ChatMessage(
        text: '¡Hola! ¿Viste las fotos que subió Martín al feed?',
        isMe: false,
        time: '14:15',
      ),
      ChatMessage(
        text: '¡Hola! Sí, quedaron increíbles. Le dejé un like recién.',
        isMe: true,
        time: '14:18',
      ),
      ChatMessage(
        text: widget.chat.lastMessage,
        isMe: false,
        time: widget.chat.time,
      ),
    ]);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isMe: true,
          time: '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        ),
      );
    });
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                widget.chat.name[0],
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.chat.name,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.chat.isOnline ? 'En línea' : '@${widget.chat.username}',
                  style: textTheme.bodySmall?.copyWith(
                    color: widget.chat.isOnline ? const Color(0xFF10B981) : colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.76,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: msg.isMe ? colorScheme.primary : colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                        bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.text,
                          style: TextStyle(
                            color: msg.isMe ? colorScheme.onPrimary : colorScheme.onSurface,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg.time,
                          style: TextStyle(
                            color: msg.isMe
                                ? colorScheme.onPrimary.withValues(alpha: 0.7)
                                : colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Input bar
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
                    onPressed: () {},
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Escribí un mensaje...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        fillColor: colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    onPressed: _sendMessage,
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
