import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../models/post_item.dart';
import '../models/user_profile.dart';
import '../screens/profile_screen.dart';
import '../services/auth_service.dart';

class PostCard extends StatefulWidget {
  final PostItem post;
  final VoidCallback? onAuthorTap;

  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _isLiked;
  late int _likesCount;
  bool _isLikeLoading = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _isLiked = widget.post.isLiked;
      _likesCount = widget.post.likesCount;
    }
  }

  Future<void> _handleToggleLike() async {
    if (_isLikeLoading) return;
    HapticFeedback.lightImpact();

    // Optimistic UI update
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
      if (_likesCount < 0) _likesCount = 0;
    });

    _isLikeLoading = true;
    final res = await AuthService().toggleLikePost(widget.post.id);
    if (!mounted) return;
    _isLikeLoading = false;

    if (res != null) {
      setState(() {
        _isLiked = res['isLiked'] as bool;
        _likesCount = res['likesCount'] as int;
        widget.post.isLiked = _isLiked;
        widget.post.likesCount = _likesCount;
      });
    }
  }

  void _navigateToAuthorProfile() {
    if (widget.onAuthorTap != null) {
      widget.onAuthorTap!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          profile: UserProfile(
            id: widget.post.authorId,
            username: widget.post.authorUsername,
            displayName: widget.post.authorName,
            avatarUrl: widget.post.authorAvatarUrl,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final authorName = widget.post.authorName;
    final authorUsername = widget.post.authorUsername;
    final authorAvatar = widget.post.authorAvatarUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Avatar
          GestureDetector(
            onTap: _navigateToAuthorProfile,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: (authorAvatar != null && authorAvatar.isNotEmpty)
                  ? NetworkImage(authorAvatar)
                  : null,
              onBackgroundImageError: (authorAvatar != null && authorAvatar.isNotEmpty)
                  ? (exception, stackTrace) {}
                  : null,
              child: (authorAvatar == null || authorAvatar.isEmpty)
                  ? Text(
                      authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),

          // Post Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Name, username, time ago)
                GestureDetector(
                  onTap: _navigateToAuthorProfile,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          authorName,
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.post.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded, size: 14, color: colorScheme.primary),
                      ],
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '@$authorUsername',
                          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· ${widget.post.timeAgo}',
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Markdown Post Content
                if (widget.post.content.trim().isNotEmpty)
                  MarkdownBody(
                    data: widget.post.content,
                    selectable: false,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                        fontSize: 15,
                      ),
                      code: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                        color: colorScheme.primary,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      codeblockPadding: const EdgeInsets.all(12),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: colorScheme.primary, width: 3.5),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                      h1: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      h2: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      h3: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),

                // Post Image Attachment
                if (widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 380),
                      width: double.infinity,
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      child: Image.network(
                        widget.post.imageUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            alignment: Alignment.center,
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              strokeWidth: 2,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 120,
                          alignment: Alignment.center,
                          child: Icon(Icons.broken_image_rounded, color: colorScheme.outline),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Interactive Actions Row (Like, Comments, Repost, Share)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Like button
                    InkWell(
                      onTap: _handleToggleLike,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 18,
                              color: _isLiked ? Colors.redAccent : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$_likesCount',
                              style: TextStyle(
                                fontSize: 13,
                                color: _isLiked ? Colors.redAccent : colorScheme.onSurfaceVariant,
                                fontWeight: _isLiked ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Comments button
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Comentarios próximamente.')),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 17, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Text(
                              '${widget.post.commentsCount}',
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Repost button
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Republicar próximamente.')),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat_rounded,
                                size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Text(
                              '${widget.post.repostsCount}',
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Share button
                    IconButton(
                      icon: Icon(Icons.share_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                      tooltip: 'Compartir',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.post.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Texto copiado al portapapeles')),
                        );
                      },
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
}
