import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_item.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'chat_conversation_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatCandidate> _candidates = [];
  bool _isLoading = true;
  bool _isStartingChat = false;
  Timer? _debounce;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    setState(() {}); // refresh the clear button
    _debounce = Timer(const Duration(milliseconds: 300), () => _loadCandidates(query));
  }

  Future<void> _loadCandidates([String query = '']) async {
    final requestId = ++_searchRequestId;
    setState(() => _isLoading = true);
    final results = await AuthService().getChatCandidates(query: query);
    // Ignore responses that arrive after a newer search was issued.
    if (mounted && requestId == _searchRequestId) {
      setState(() {
        _candidates = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSelectCandidate(ChatCandidate candidate) async {
    if (_isStartingChat) return;

    if (!candidate.canMessage) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.lock_rounded, size: 36, color: Theme.of(context).colorScheme.primary),
          title: const Text('Cuenta privada'),
          content: Text(
            'No podés enviarle mensajes a @${candidate.username} porque tiene una cuenta privada.\n\nPara poder chatear, necesitás seguir a este usuario y que acepte tu solicitud de seguimiento.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isStartingChat = true);

    final res = await AuthService().startConversationWithUser(candidate.id);
    if (!mounted) return;
    setState(() => _isStartingChat = false);

    if (res['success'] == true && res['conversationId'] != null) {
      final convId = res['conversationId'] as String;
      final other = res['otherParticipant'] as UserProfile? ??
          UserProfile(
            id: candidate.id,
            username: candidate.username,
            displayName: candidate.displayName,
            avatarUrl: candidate.avatarUrl,
            isVerified: candidate.isVerified,
            isPrivate: candidate.isPrivate,
          );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatConversationScreen(
            conversationId: convId,
            otherParticipant: other,
          ),
        ),
      );
    } else {
      final error = res['error'] as String? ?? 'No se pudo iniciar el chat';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Nuevo mensaje', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          // Search input field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o @usuario...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _debounce?.cancel();
                          _searchController.clear();
                          _loadCandidates();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          if (_isStartingChat)
            const LinearProgressIndicator(),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _candidates.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_search_rounded, size: 54, color: colorScheme.outline),
                              const SizedBox(height: 16),
                              Text(
                                'No se encontraron usuarios',
                                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Probá buscando con otro nombre de usuario.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _candidates.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 72,
                          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                        ),
                        itemBuilder: (context, index) {
                          final candidate = _candidates[index];
                          final avatarUrl = candidate.avatarUrl;
                          final displayName = candidate.displayName;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              radius: 22,
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
                                      ),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: candidate.canMessage
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (candidate.isVerified) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.verified_rounded, size: 14, color: colorScheme.primary),
                                ],
                                if (candidate.isPrivate) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 13,
                                    color: candidate.canMessage
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.error,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              !candidate.canMessage
                                  ? 'Cuenta privada · Requiere aprobación previa'
                                  : '@${candidate.username}',
                              style: textTheme.bodySmall?.copyWith(
                                color: candidate.canMessage
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.error.withValues(alpha: 0.8),
                              ),
                            ),
                            trailing: candidate.canMessage
                                ? Icon(Icons.chat_bubble_outline_rounded,
                                    size: 20, color: colorScheme.primary)
                                : Icon(Icons.lock_rounded, size: 18, color: colorScheme.outline),
                            onTap: () => _handleSelectCandidate(candidate),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
