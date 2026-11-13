import 'package:flutter/material.dart';
import '../models/post_comment.dart';
import '../models/post_item.dart';
import '../screens/profile_screen.dart';
import '../services/auth_service.dart';
import 'report_dialog.dart';

/// Opens comments for [post] in a modern modal bottom sheet that overlays
/// the current screen (e.g. fullscreen video/image or feed) without losing context.
Future<void> showPostCommentsSheet(
  BuildContext context,
  PostItem post, {
  VoidCallback? onCommentsChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PostCommentsSheet(
      post: post,
      onCommentsChanged: onCommentsChanged,
    ),
  );
}

class _PostCommentsSheet extends StatefulWidget {
  final PostItem post;
  final VoidCallback? onCommentsChanged;

  const _PostCommentsSheet({
    required this.post,
    this.onCommentsChanged,
  });

  @override
  State<_PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<_PostCommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<PostComment> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  PostComment? _replyingTo;

  String? get _myId => AuthService().currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comments = await AuthService().getComments(widget.post.id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (comments != null) {
        _comments = comments;
        widget.post.commentsCount = comments.length;
        widget.onCommentsChanged?.call();
      }
    });
  }

  void _startReplyTo(PostComment comment) {
    setState(() {
      _replyingTo = comment;
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final parent = _replyingTo;
    setState(() => _isSending = true);

    final result = await AuthService().addComment(
      widget.post.id,
      text,
      parentId: parent?.id,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    final comment = result.comment;
    if (comment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'No se pudo enviar el comentario')),
      );
      return;
    }

    _controller.clear();
    setState(() {
      _replyingTo = null;
      _comments.add(comment);
      widget.post.commentsCount = result.commentsCount ?? _comments.length;
      widget.onCommentsChanged?.call();
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

  Future<void> _toggleLike(PostComment comment) async {
    final previousLiked = comment.isLiked;
    final previousCount = comment.likesCount;

    setState(() {
      comment.isLiked = !previousLiked;
      comment.likesCount = previousLiked ? (previousCount - 1).clamp(0, 999999) : previousCount + 1;
    });

    final res = await AuthService().toggleCommentLike(widget.post.id, comment.id);
    if (!mounted) return;

    if (!res.success) {
      setState(() {
        comment.isLiked = previousLiked;
        comment.likesCount = previousCount;
      });
    } else {
      setState(() {
        comment.isLiked = res.isLiked;
        comment.likesCount = res.likesCount;
      });
    }
  }

  Future<void> _delete(PostComment comment) async {
    final count = await AuthService().deleteComment(widget.post.id, comment.id);
    if (!mounted) return;
    if (count != null) {
      setState(() {
        if (_replyingTo?.id == comment.id) _replyingTo = null;
        _comments.removeWhere((c) => c.id == comment.id || c.parentId == comment.id);
        widget.post.commentsCount = count;
        widget.onCommentsChanged?.call();
      });
    }
  }

  List<({PostComment comment, int depth, String? replyToUsername})> _buildThreadedComments() {
    final commentsById = {for (final c in _comments) c.id: c};
    final childrenByParent = <String, List<PostComment>>{};

    for (final c in _comments) {
      final pid = c.parentId;
      if (pid != null && commentsById.containsKey(pid)) {
        childrenByParent.putIfAbsent(pid, () => []).add(c);
      }
    }

    final result = <({PostComment comment, int depth, String? replyToUsername})>[];

    void addSubtree(PostComment node, int depth) {
      final parentNode = node.parentId != null ? commentsById[node.parentId] : null;
      final replyTo = parentNode?.author.username;
      result.add((comment: node, depth: depth, replyToUsername: replyTo));

      final children = childrenByParent[node.id] ?? const [];
      for (final child in children) {
        addSubtree(child, (depth + 1).clamp(0, 4));
      }
    }

    for (final c in _comments) {
      if (c.parentId == null || !commentsById.containsKey(c.parentId)) {
        addSubtree(c, 0);
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final threaded = _buildThreadedComments();

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.75,
      ),
      margin: EdgeInsets.only(bottom: keyboardHeight),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle and header
            Container(
              padding: const EdgeInsets.only(top: 10, bottom: 8, left: 16, right: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Comentarios (${_comments.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Comments list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : threaded.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 42,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Aún no hay comentarios',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sé el primero en opinar',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: threaded.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = threaded[index];
                            return _buildCommentTile(item.comment, item.depth, item.replyToUsername, colorScheme, theme);
                          },
                        ),
            ),

            // Replying banner if active
            if (_replyingTo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Respondiendo a @${_replyingTo!.author.username}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _cancelReply,
                    ),
                  ],
                ),
              ),

            // Input field row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: _replyingTo != null
                            ? 'Responde a @${_replyingTo!.author.username}...'
                            : 'Agregá un comentario...',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_upward_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentTile(
    PostComment comment,
    int depth,
    String? replyToUsername,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final isMe = comment.author.id == _myId;
    final leftPadding = (depth * 20.0).clamp(0.0, 60.0);

    return Padding(
      padding: EdgeInsets.only(left: leftPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    profile: comment.author,
                  ),
                ),
              );
            },
            child: CircleAvatar(
              radius: 16,
              backgroundImage: (comment.author.avatarUrl != null && comment.author.avatarUrl!.isNotEmpty)
                  ? NetworkImage(comment.author.avatarUrl!)
                  : null,
              child: (comment.author.avatarUrl == null || comment.author.avatarUrl!.isEmpty)
                  ? Text(
                      comment.author.displayName.isNotEmpty
                          ? comment.author.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 10),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (author name, username, time)
                Row(
                  children: [
                    Text(
                      comment.author.displayName,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '@${comment.author.username}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${comment.timeAgo}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // Reply indicator if reply
                if (replyToUsername != null && depth > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'En respuesta a @$replyToUsername',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // Comment text
                Text(
                  comment.content,
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: 6),

                // Actions: Reply & Delete
                Row(
                  children: [
                    InkWell(
                      onTap: () => _startReplyTo(comment),
                      child: Text(
                        'Responder',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 14),
                      InkWell(
                        onTap: () => _delete(comment),
                        child: Text(
                          'Eliminar',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 14),
                    InkWell(
                      onTap: () => showReportContentDialog(
                        context,
                        commentId: comment.id,
                        targetTitle: 'el comentario de @${comment.author.username}',
                      ),
                      child: Text(
                        'Reportar',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Like button on the right
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  comment.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 16,
                  color: comment.isLiked ? Colors.redAccent : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _toggleLike(comment),
              ),
              if (comment.likesCount > 0)
                Text(
                  '${comment.likesCount}',
                  style: TextStyle(
                    fontSize: 11,
                    color: comment.isLiked ? Colors.redAccent : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: comment.isLiked ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
