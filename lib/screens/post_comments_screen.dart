import 'package:flutter/material.dart';
import '../models/post_comment.dart';
import '../models/post_item.dart';
import '../services/auth_service.dart';
import '../widgets/post_card.dart';
import 'profile_screen.dart';

/// A post with its comments and a field to add one. Keeps the post's
/// comment count up to date so the card shows it when coming back.
class PostCommentsScreen extends StatefulWidget {
  final PostItem post;

  const PostCommentsScreen({super.key, required this.post});

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<PostComment> _comments = [];
  bool _isLoading = true;
  bool _isUnavailable = false;
  bool _isSending = false;

  void _setCount(int count) => widget.post.commentsCount = count;

  String? get _myId => AuthService().currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comments = await AuthService().getComments(widget.post.id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isUnavailable = comments == null;
      if (comments != null) {
        _comments = comments;
        _setCount(comments.length);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final result = await AuthService().addComment(widget.post.id, text);
    if (!mounted) return;
    setState(() => _isSending = false);

    final comment = result.comment;
    if (comment == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'No se pudo comentar')));
      return;
    }
    _controller.clear();
    setState(() {
      _comments.add(comment);
      _setCount(result.commentsCount ?? _comments.length);
    });
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

  Future<void> _delete(PostComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar comentario'),
        content: const Text('¿Querés borrar este comentario?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final count = await AuthService().deleteComment(widget.post.id, comment.id);
    if (!mounted) return;
    if (count == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo borrar el comentario')));
      return;
    }
    setState(() {
      _comments.removeWhere((c) => c.id == comment.id);
      _setCount(count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
            decoration: isDesktop
                ? BoxDecoration(
                    color: colorScheme.surface,
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                  )
                : null,
            child: AppBar(
              title: const Text('Comentarios'),
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: colorScheme.surface,
            ),
          ),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          decoration: isDesktop
              ? BoxDecoration(
                  color: colorScheme.surface,
                  border: Border.symmetric(
                    vertical: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                )
              : null,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  children: [
                    PostCard(post: widget.post, showCommentsButton: false),
                    Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_isUnavailable)
                      _buildMessage(
                        Icons.cloud_off_rounded,
                        'Los comentarios todavía no están disponibles',
                        'Se activan cuando se actualice el servidor.',
                        colorScheme,
                        textTheme,
                      )
                    else if (_comments.isEmpty)
                      _buildMessage(
                        Icons.chat_bubble_outline_rounded,
                        'Todavía no hay comentarios',
                        'Sé la primera persona en comentar.',
                        colorScheme,
                        textTheme,
                      )
                    else
                      ..._comments.map((c) => _buildComment(c, colorScheme, textTheme)),
                  ],
                ),
              ),
              _buildInput(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(IconData icon, String title, String body, ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
      child: Column(
        children: [
          Icon(icon, size: 44, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildComment(PostComment comment, ColorScheme colorScheme, TextTheme textTheme) {
    final author = comment.author;
    final avatarUrl = author.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final canDelete = _myId != null && (comment.author.id == _myId || widget.post.authorId == _myId);
    void openAuthor() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProfileScreen(profile: author)),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: openAuthor,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              onBackgroundImageError: hasAvatar ? (_, _) {} : null,
              child: hasAvatar
                  ? null
                  : Text(
                      author.displayName.isNotEmpty ? author.displayName[0].toUpperCase() : '?',
                      style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: openAuthor,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: author.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(
                          text: '  ${comment.timeAgo}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                    style: textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(comment.content, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              tooltip: 'Borrar comentario',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.onSurfaceVariant),
              onPressed: () => _delete(comment),
            ),
        ],
      ),
    );
  }

  Widget _buildInput(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isUnavailable,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Escribí un comentario...',
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  fillColor: colorScheme.surface,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Comentar',
              onPressed: _isSending || _isUnavailable ? null : _send,
              icon: _isSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
