import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_item.dart';
import '../screens/new_chat_screen.dart';
import '../services/auth_service.dart';
import '../services/chat_crypto.dart';
import '../services/chat_unread_service.dart';

/// Sidebar listing all conversations, with search, decrypted previews,
/// unread badges, and an active selection highlight for desktop master-detail views.
class ChatsSidebar extends StatefulWidget {
  final String? selectedConversationId;
  final ValueChanged<ChatItem> onSelectChat;
  final Widget? headerLeading;
  final VoidCallback? onNewChat;

  const ChatsSidebar({
    super.key,
    this.selectedConversationId,
    required this.onSelectChat,
    this.headerLeading,
    this.onNewChat,
  });

  @override
  State<ChatsSidebar> createState() => _ChatsSidebarState();
}

class _ChatsSidebarState extends State<ChatsSidebar> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatItem> _chats = [];
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isFetching = false;
  Timer? _refreshTimer;

  /// Decrypted last messages: conversationId -> (ciphertext, preview)
  final Map<String, (String, String)> _previews = {};

  @override
  void initState() {
    super.initState();
    AuthService().chatsRefreshNotifier.addListener(_loadChats);
    _loadChats();

    // Periodic refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadChats());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    AuthService().chatsRefreshNotifier.removeListener(_loadChats);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    if (_isFetching) return;
    if (!AuthService().isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ChatUnreadService().clear();
      });
      if (_isLoading && mounted) setState(() => _isLoading = false);
      return;
    }
    _isFetching = true;
    try {
      final list = await AuthService().getConversations();
      if (mounted) {
        setState(() {
          if (list.isNotEmpty || _chats.isEmpty) {
            _chats = list;
          }
          _isLoading = false;
        });
        ChatUnreadService().update(_chats);
        await _decryptPreviews();
      }
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _decryptPreviews() async {
    if (!_chats.any((c) => ChatCipher.isEncrypted(c.lastMessage))) return;
    if (ChatCrypto().status.value == ChatCryptoStatus.checking) await ChatCrypto().refresh();

    var changed = false;
    for (final chat in List.of(_chats)) {
      final other = chat.otherParticipant;
      if (other == null || !ChatCipher.isEncrypted(chat.lastMessage)) continue;
      if (_previews[chat.id]?.$1 == chat.lastMessage) continue;

      final key = await ChatCrypto().keyForConversation(chat.id, other.id);
      final payload = key != null ? await ChatCipher.decryptPayload(chat.lastMessage, key) : null;
      if (payload != null) {
        _previews[chat.id] = (chat.lastMessage, payload.preview);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  String _previewOf(ChatItem chat) {
    if (!ChatCipher.isEncrypted(chat.lastMessage)) return chat.lastMessage;
    final preview = _previews[chat.id];
    return preview != null && preview.$1 == chat.lastMessage ? preview.$2 : '🔒 Mensaje cifrado';
  }

  List<ChatItem> get _filteredChats {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _chats;
    return _chats.where((c) {
      return c.displayName.toLowerCase().contains(query) ||
          c.username.toLowerCase().contains(query) ||
          _previewOf(c).toLowerCase().contains(query);
    }).toList();
  }

  void _openNewChat() async {
    if (widget.onNewChat != null) {
      widget.onNewChat!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
    _loadChats();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      color: colorScheme.surface,
      child: Column(
        children: [
          // Header / Toolbar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                if (widget.headerLeading != null) ...[
                  widget.headerLeading!,
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: _isSearching
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Buscar chats...',
                            border: InputBorder.none,
                            isDense: true,
                            hintStyle: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Text(
                          'Mensajes',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          ),
                        ),
                ),
                IconButton(
                  tooltip: _isSearching ? 'Cerrar búsqueda' : 'Buscar mensajes',
                  icon: Icon(
                    _isSearching ? Icons.close_rounded : Icons.search_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_isSearching) {
                        _isSearching = false;
                        _searchController.clear();
                      } else {
                        _isSearching = true;
                      }
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Nuevo mensaje',
                  icon: Icon(Icons.edit_square, color: colorScheme.primary, size: 20),
                  onPressed: _openNewChat,
                ),
              ],
            ),
          ),

          // Chats list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadChats,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredChats.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 40,
                                    color: colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchController.text.isNotEmpty
                                        ? 'Sin resultados'
                                        : 'Aún no tenés chats',
                                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _searchController.text.isNotEmpty
                                        ? 'Probá con otro término.'
                                        : 'Iniciá una nueva conversación tocando el botón superior.',
                                    textAlign: TextAlign.center,
                                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                          itemCount: _filteredChats.length,
                          itemBuilder: (context, index) {
                            final chat = _filteredChats[index];
                            final isSelected = widget.selectedConversationId == chat.id;
                            final avatarUrl = chat.avatarUrl;
                            final displayName = chat.displayName;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Material(
                                color: isSelected
                                    ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: colorScheme.primaryContainer,
                                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  onBackgroundImageError: (avatarUrl != null && avatarUrl.isNotEmpty)
                                      ? (_, _) {}
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
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.bodyMedium?.copyWith(
                                                fontWeight: chat.unreadCount > 0 || isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (chat.isVerified) ...[
                                            const SizedBox(width: 4),
                                            Icon(Icons.verified_rounded, size: 13, color: colorScheme.primary),
                                          ],
                                          if (chat.isPrivate) ...[
                                            const SizedBox(width: 4),
                                            Icon(Icons.lock_rounded, size: 11, color: colorScheme.onSurfaceVariant),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      chat.timeFormatted,
                                      style: textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: chat.unreadCount > 0
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _previewOf(chat).isNotEmpty ? _previewOf(chat) : 'Conversación iniciada',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: chat.unreadCount > 0
                                              ? colorScheme.onSurface
                                              : colorScheme.onSurfaceVariant,
                                          fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (chat.unreadCount > 0)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${chat.unreadCount}',
                                          style: TextStyle(
                                            color: colorScheme.onPrimary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () => widget.onSelectChat(chat),
                              ),
                            ),
                          );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
