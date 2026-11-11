import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_item.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/chat_crypto.dart';
import '../services/chat_unread_service.dart';
import 'chat_conversation_screen.dart';
import 'new_chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatItem> _chats = [];
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isFetching = false;
  Timer? _refreshTimer;

  /// Decrypted last messages, by conversation id and the ciphertext they came from.
  final Map<String, (String, String)> _previews = {};

  @override
  void initState() {
    super.initState();
    AuthService().chatsRefreshNotifier.addListener(_loadChats);
    _loadChats();

    // Keep the inbox (new conversations, last message, unread badges) fresh
    // without requiring a manual pull-to-refresh.
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
          // Conversations can't be deleted, so an empty result after having
          // chats means the request failed: keep showing what we had.
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

  /// The server only has ciphertext for encrypted chats, so their previews are decrypted here.
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
    _loadChats();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar en mensajes...',
                  border: InputBorder.none,
                  hintStyle: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              )
            : Text(
                'Mensajes',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Cerrar búsqueda' : 'Buscar mensajes',
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
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
            icon: Icon(Icons.edit_square, color: colorScheme.primary),
            onPressed: _openNewChat,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadChats,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _filteredChats.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  size: 54, color: colorScheme.primary),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isNotEmpty
                                    ? 'Sin resultados para la búsqueda'
                                    : 'Aún no tenés mensajes',
                                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchController.text.isNotEmpty
                                    ? 'Intentá buscar con otros términos.'
                                    : 'Iniciá una nueva conversación tocando el botón de nuevo mensaje.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                              if (_searchController.text.isEmpty) ...[
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: _openNewChat,
                                  icon: const Icon(Icons.send_rounded, size: 18),
                                  label: const Text('Iniciar nuevo chat'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filteredChats.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 72,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                    itemBuilder: (context, index) {
                      final chat = _filteredChats[index];
                      final avatarUrl = chat.avatarUrl;
                      final displayName = chat.displayName;
                      final other = chat.otherParticipant ??
                          UserProfile(
                            id: chat.id,
                            username: chat.username,
                            displayName: displayName,
                            avatarUrl: avatarUrl,
                          );

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: CircleAvatar(
                          radius: 24,
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
                                    fontSize: 18,
                                  ),
                                )
                              : null,
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight:
                                            chat.unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (chat.isVerified) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.verified_rounded, size: 14, color: colorScheme.primary),
                                  ],
                                  if (chat.isPrivate) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.lock_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              chat.timeFormatted,
                              style: textTheme.bodySmall?.copyWith(
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
                                _previewOf(chat).isNotEmpty
                                    ? _previewOf(chat)
                                    : 'Conversación iniciada',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: chat.unreadCount > 0
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight:
                                      chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
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
                              Icon(Icons.done_all_rounded, size: 15, color: colorScheme.primary),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatConversationScreen(
                                conversationId: chat.id,
                                otherParticipant: other,
                              ),
                            ),
                          );
                          _loadChats();
                        },
                      );
                    },
                  ),
      ),
    );
  }
}
