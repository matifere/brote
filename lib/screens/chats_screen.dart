import 'package:flutter/material.dart';
import 'chat_conversation_screen.dart';

class ChatItem {
  final String id;
  final String name;
  final String username;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool isOnline;
  final bool isRead;

  ChatItem({
    required this.id,
    required this.name,
    required this.username,
    required this.lastMessage,
    required this.time,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isRead = true,
  });
}

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final List<ChatItem> _chats = [
    ChatItem(
      id: '1',
      name: 'Sofía Valenzuela',
      username: 'sofia_v',
      lastMessage: '¡Che, viste el video que subieron recién? Se fue viral mal 😂',
      time: '14:20',
      unreadCount: 1,
      isOnline: true,
      isRead: false,
    ),
    ChatItem(
      id: '2',
      name: 'Martín Morales',
      username: 'morales_builds',
      lastMessage: 'Te pasé las fotos del recital de anoche 📸',
      time: '11:05',
      unreadCount: 0,
      isOnline: true,
      isRead: true,
    ),
    ChatItem(
      id: '3',
      name: 'Elena Rostova',
      username: 'elena_dev',
      lastMessage: '¿Nos sumamos al stream hoy a la noche?',
      time: 'Ayer',
      unreadCount: 0,
      isOnline: false,
      isRead: true,
    ),
    ChatItem(
      id: '4',
      name: 'Grupo Amigos',
      username: 'los_pibes',
      lastMessage: 'Lucas: ¿A qué hora nos encontramos en la previa?',
      time: 'Lun',
      unreadCount: 3,
      isOnline: false,
      isRead: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Mensajes',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar mensajes',
            icon: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
            onPressed: () {},
          ),
          IconButton(
            tooltip: 'Nuevo mensaje',
            icon: Icon(Icons.edit_square, color: colorScheme.primary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Iniciando nuevo chat...')),
              );
            },
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _chats.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          indent: 72,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          final chat = _chats[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    chat.name[0],
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (chat.isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981), // Fresh green indicator
                        shape: BoxShape.circle,
                        border: Border.all(color: colorScheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    chat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  chat.time,
                  style: textTheme.bodySmall?.copyWith(
                    color: chat.unreadCount > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: Text(
                    chat.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: chat.unreadCount > 0 ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                      fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (chat.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${chat.unreadCount}',
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (chat.isRead)
                  Icon(Icons.done_all_rounded, size: 16, color: colorScheme.primary),
              ],
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatConversationScreen(chat: chat),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
