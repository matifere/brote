import 'package:flutter/material.dart';
import '../models/post_comment.dart';
import '../models/post_item.dart';
import '../services/auth_service.dart';
import '../widgets/post_card.dart';
import '../widgets/report_dialog.dart';
import 'profile_screen.dart';

/// A post with its comments organized as threads (replies) and comment likes.
/// Keeps the post's comment count up to date so the card shows it when coming back.
class PostCommentsScreen extends StatefulWidget {
  final PostItem post;

  const PostCommentsScreen({super.key, required this.post});

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<PostComment> _comments = [];
  bool _isLoading = true;
  bool _isUnavailable = false;
  bool _isSending = false;

  /// Comment being replied to (null if top-level comment)
  PostComment? _replyingTo;

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
    _focusNode.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'No se pudo comentar')));
      return;
    }
    _controller.clear();
    setState(() {
      _replyingTo = null;
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

  Future<void> _toggleLike(PostComment comment) async {
    final previousLiked = comment.isLiked;
    final previousCount = comment.likesCount;

    // Optimistic update
    setState(() {
      comment.isLiked = !previousLiked;
      comment.likesCount = previousLiked ? (previousCount - 1).clamp(0, 999999) : previousCount + 1;
    });

    final res = await AuthService().toggleCommentLike(widget.post.id, comment.id);
    if (!mounted) return;

    if (!res.success) {
      // Rollback on failure
      setState(() {
        comment.isLiked = previousLiked;
        comment.likesCount = previousCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'No se pudo actualizar el me gusta')),
      );
    } else {
      setState(() {
        comment.isLiked = res.isLiked;
        comment.likesCount = res.likesCount;
      });
    }
  }

  Future<void> _delete(PostComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar comentario'),
        content: const Text('¿Querés borrar este comentario y sus respuestas?'),
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
      if (_replyingTo?.id == comment.id) {
        _replyingTo = null;
      }
      _removeCommentAndDescendants(comment.id);
      _setCount(count);
    });
  }

  void _removeCommentAndDescendants(String commentId) {
    final toRemove = <String>{commentId};
    bool addedAny;
    do {
      addedAny = false;
      for (final c in _comments) {
        if (c.parentId != null && toRemove.contains(c.parentId) && !toRemove.contains(c.id)) {
          toRemove.add(c.id);
          addedAny = true;
        }
      }
    } while (addedAny);
    _comments.removeWhere((c) => toRemove.contains(c.id));
  }

  /// Builds a linear list of comments ordered by conversation threads.
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
      final parent = node.parentId != null ? commentsById[node.parentId] : null;
      result.add((
        comment: node,
        depth: depth.clamp(0, 2),
        replyToUsername: node.replyToUsername ?? parent?.author.username,
      ));
      final children = childrenByParent[node.id] ?? const [];
      for (final child in children) {
        addSubtree(child, depth + 1);
      }
    }

    // Root comments: parentId is null or parent doesn't exist in the list
    for (final c in _comments) {
      if (c.parentId == null || !commentsById.containsKey(c.parentId)) {
        addSubtree(c, 0);
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;
    final threadedItems = _buildThreadedComments();

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
                      ...threadedItems.map((item) => _buildCommentRow(
                            item.comment,
                            item.depth,
                            item.replyToUsername,
                            colorScheme,
                            textTheme,
                          )),
                  ],
                ),
              ),
              _buildInputArea(colorScheme, textTheme),
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

  Widget _buildCommentRow(
    PostComment comment,
    int depth,
    String? replyToUsername,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final author = comment.author;
    final avatarUrl = author.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final canDelete = _myId != null && (comment.author.id == _myId || widget.post.authorId == _myId);
    final isReply = depth > 0;
    final indentLeft = depth == 0 ? 0.0 : (depth == 1 ? 28.0 : 48.0);
    final avatarRadius = isReply ? 14.0 : 17.0;

    void openAuthor() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProfileScreen(profile: author)),
        );

    return Container(
      margin: EdgeInsets.only(left: indentLeft),
      decoration: BoxDecoration(
        border: isReply
            ? Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 2,
                ),
              )
            : Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
      ),
      padding: EdgeInsets.fromLTRB(isReply ? 12 : 16, 10, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: openAuthor,
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              onBackgroundImageError: hasAvatar ? (_, _) {} : null,
              child: hasAvatar
                  ? null
                  : Text(
                      author.displayName.isNotEmpty ? author.displayName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: isReply ? 11 : 13,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author row
                Row(
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: openAuthor,
                        child: Text(
                          author.displayName,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '@${author.username}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '·  ${comment.timeAgo}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                // Reply indicator pill
                if (isReply && replyToUsername != null && replyToUsername.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Respondiendo a @$replyToUsername',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],

                const SizedBox(height: 3),
                // Content
                Text(
                  comment.content,
                  style: textTheme.bodyMedium?.copyWith(height: 1.35),
                ),

                const SizedBox(height: 6),
                // Action row: Like, Reply, Delete
                Row(
                  children: [
                    // Like button
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _toggleLike(comment),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 16,
                              color: comment.isLiked ? colorScheme.error : colorScheme.onSurfaceVariant,
                            ),
                            if (comment.likesCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${comment.likesCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: comment.isLiked ? colorScheme.error : colorScheme.onSurfaceVariant,
                                  fontWeight: comment.isLiked ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Reply button
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _startReplyTo(comment),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.reply_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              'Responder',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Report button
                    if (comment.author.id != _myId)
                      IconButton(
                        tooltip: 'Reportar comentario',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.flag_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                        onPressed: () => showReportContentDialog(
                          context,
                          commentId: comment.id,
                          targetTitle: 'comentario',
                        ),
                      ),

                    // Delete button
                    if (canDelete)
                      IconButton(
                        tooltip: 'Borrar comentario',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                        onPressed: () => _delete(comment),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme, TextTheme textTheme) {
    final replying = _replyingTo;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Replying Banner
            if (replying != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Respondiendo a @${replying.author.username}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancelar respuesta',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _cancelReply,
                    ),
                  ],
                ),
              ),

            // Text input row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: !_isUnavailable,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: replying != null
                            ? 'Escribí tu respuesta...'
                            : 'Escribí un comentario...',
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
          ],
        ),
      ),
    );
  }
}
