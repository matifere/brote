import 'package:flutter/material.dart';
import '../models/chat_item.dart';
import '../models/user_profile.dart';
import '../widgets/chats_sidebar.dart';
import 'chat_conversation_screen.dart';
import 'new_chat_screen.dart';

/// Chats screen with responsive layout:
/// - Mobile (< 720px wide): single inbox list, tapping a chat pushes full conversation.
/// - Desktop (>= 720px wide): master-detail split screen with chats list on the left and active conversation on the right.
class ChatsScreen extends StatefulWidget {
  final String? initialConversationId;

  const ChatsScreen({super.key, this.initialConversationId});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  ChatItem? _selectedChat;

  @override
  void initState() {
    super.initState();
  }

  void _onSelectChatMobile(ChatItem chat) async {
    final other = chat.otherParticipant ??
        UserProfile(
          id: chat.id,
          username: chat.username,
          displayName: chat.displayName,
          avatarUrl: chat.avatarUrl,
        );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          conversationId: chat.id,
          otherParticipant: other,
        ),
      ),
    );
  }

  void _onSelectChatDesktop(ChatItem chat) {
    setState(() {
      _selectedChat = chat;
    });
  }

  void _openNewChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.sizeOf(context);
        final isDesktop = media.width >= 720 && media.width > media.height && constraints.maxWidth >= 550;

        if (!isDesktop) {
          // Mobile single-pane inbox
          return Scaffold(
            backgroundColor: colorScheme.surface,
            body: ChatsSidebar(
              selectedConversationId: null,
              onSelectChat: _onSelectChatMobile,
              onNewChat: _openNewChat,
            ),
          );
        }

        // Desktop Master-Detail split view
        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: Row(
            children: [
              // Left Pane: All Available Chats Menu
              SizedBox(
                width: 320,
                child: ChatsSidebar(
                  selectedConversationId: _selectedChat?.id ?? widget.initialConversationId,
                  onSelectChat: _onSelectChatDesktop,
                  onNewChat: _openNewChat,
                ),
              ),

              // Vertical divider between chats list and active conversation
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),

              // Right Pane: Active Conversation or Placeholder
              Expanded(
                child: _selectedChat != null
                    ? ChatConversationScreen(
                        key: ValueKey(_selectedChat!.id),
                        conversationId: _selectedChat!.id,
                        otherParticipant: _selectedChat!.otherParticipant ??
                            UserProfile(
                              id: _selectedChat!.id,
                              username: _selectedChat!.username,
                              displayName: _selectedChat!.displayName,
                              avatarUrl: _selectedChat!.avatarUrl,
                            ),
                        isEmbedded: true,
                      )
                    : _buildEmptyPlaceholder(colorScheme, textTheme),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyPlaceholder(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              ),
              child: Icon(Icons.chat_bubble_outline_rounded, size: 52, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Tus mensajes',
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Elegí una conversación del menú de la izquierda para empezar a chatear o iniciá un nuevo chat.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openNewChat,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Nuevo mensaje'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
