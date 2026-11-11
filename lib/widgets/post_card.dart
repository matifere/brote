import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../models/post_item.dart';
import '../models/rating.dart';
import '../models/user_profile.dart';
import '../screens/post_comments_screen.dart';
import '../screens/profile_screen.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import 'full_screen_image_viewer.dart';
import 'rating_stars.dart';

class PostCard extends StatefulWidget {
  final PostItem post;
  final VoidCallback? onAuthorTap;

  /// False inside the comments screen, where the comments are already shown.
  final bool showCommentsButton;

  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
    this.showCommentsButton = true,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  bool _isLikeLoading = false;
  String? _moviePosterUrl;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
    _commentsCount = widget.post.commentsCount;
    _loadPosterIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The feed rebuilds with fresh PostItem instances on every reload, so
    // compare identity (not id) to pick up updated like state and counts.
    if (!identical(oldWidget.post, widget.post) && !_isLikeLoading) {
      _isLiked = widget.post.isLiked;
      _likesCount = widget.post.likesCount;
      _commentsCount = widget.post.commentsCount;
      _loadPosterIfNeeded();
    }
  }

  bool get _isOwnPost => AuthService().currentUser?.id == widget.post.authorId;

  Future<void> _openComments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostCommentsScreen(post: widget.post)),
    );
    // The comments screen keeps the post's count up to date
    if (mounted) setState(() => _commentsCount = widget.post.commentsCount);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar publicación'),
        content: const Text('Se borra para siempre, con sus me gusta y comentarios.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final deleted = await AuthService().deletePost(widget.post.id);
    messenger.showSnackBar(
      SnackBar(content: Text(deleted ? 'Publicación borrada' : 'No se pudo borrar la publicación')),
    );
  }

  void _loadPosterIfNeeded() {
    final parsed = widget.post.parsedContent;
    if (parsed.review != null && parsed.review!.category == RatingCategory.movie) {
      if (widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty) {
        _moviePosterUrl = widget.post.imageUrl;
      } else {
        final cached = CatalogService().getCachedPoster(parsed.review!.title, year: parsed.review!.year);
        if (cached != null) {
          _moviePosterUrl = cached;
        } else {
          CatalogService().getMoviePoster(parsed.review!.title, year: parsed.review!.year).then((url) {
            if (mounted && url != null) {
              setState(() => _moviePosterUrl = url);
            }
          });
        }
      }
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
    _isLikeLoading = false;
    if (!mounted) return;

    setState(() {
      if (res != null) {
        _isLiked = res['isLiked'] as bool;
        _likesCount = res['likesCount'] as int;
      } else {
        // Request failed: revert the optimistic update.
        _isLiked = widget.post.isLiked;
        _likesCount = widget.post.likesCount;
      }
      widget.post.isLiked = _isLiked;
      widget.post.likesCount = _likesCount;
    });

    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo registrar el me gusta. Intentá de nuevo.')),
      );
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
    final parsed = widget.post.parsedContent;
    final timeLeft = widget.post.timeLeft;
    final rawImages = widget.post.imageUrls.isNotEmpty
        ? widget.post.imageUrls
        : (widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty
            ? [widget.post.imageUrl!]
            : const <String>[]);
    final isCoverImage = parsed.review != null &&
        parsed.review!.category == RatingCategory.movie &&
        rawImages.length == 1 &&
        rawImages.first == (_moviePosterUrl ?? widget.post.imageUrl);
    final postImages = isCoverImage ? const <String>[] : rawImages;

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
                // Header (Name, username, time ago) and, on your posts, a menu
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
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
                            if (timeLeft != null) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.timelapse_rounded, size: 13, color: colorScheme.tertiary),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Tooltip(
                                  message: 'Publicación de 24 h',
                                  child: Text(
                                    timeLeft,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(color: colorScheme.tertiary),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_isOwnPost)
                      SizedBox(
                        width: 28,
                        height: 24,
                        child: PopupMenuButton<String>(
                          tooltip: 'Opciones',
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          icon: Icon(Icons.more_horiz_rounded, color: colorScheme.onSurfaceVariant),
                          onSelected: (_) => _confirmDelete(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('Borrar publicación')),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Review of a movie or music
                if (parsed.review != null) _buildReview(parsed.review!, colorScheme, textTheme),

                // Markdown Post Content
                if (parsed.body.isNotEmpty)
                  MarkdownBody(
                    data: parsed.body,
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

                // Post Media Attachment(s) (skip if already displayed as movie poster in review)
                if (postImages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildMediaGrid(postImages, colorScheme),
                ],

                const SizedBox(height: 14),

                // Interactive Actions Row (Like, Comments, Share)
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
                    if (widget.showCommentsButton)
                      InkWell(
                        onTap: _openComments,
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
                                '$_commentsCount',
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
                        final text = [
                          if (parsed.review != null) parsed.review!.encodeLine(),
                          if (parsed.body.isNotEmpty) parsed.body,
                        ].join('\n\n');
                        final imageUrl = widget.post.imageUrl ?? '';
                        final shareText = [
                          if (text.isNotEmpty) text,
                          if (imageUrl.isNotEmpty) imageUrl,
                        ].join('\n\n');
                        Clipboard.setData(ClipboardData(text: shareText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(text.isNotEmpty
                                ? 'Texto copiado al portapapeles'
                                : 'Enlace de la imagen copiado al portapapeles'),
                          ),
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

  Widget _buildReview(RatedItem review, ColorScheme colorScheme, TextTheme textTheme) {
    final isMovie = review.category == RatingCategory.movie;
    final posterUrl = isMovie ? (_moviePosterUrl ?? widget.post.imageUrl) : null;
    final hasPoster = posterUrl != null && posterUrl.isNotEmpty;
    final heroTag = 'review-poster-${widget.post.id}';

    Widget posterBox = Container(
      width: hasPoster ? 48 : 40,
      height: hasPoster ? 70 : 40,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(hasPoster ? 8 : 10),
      ),
      child: Icon(
        isMovie ? Icons.movie_outlined : Icons.music_note_outlined,
        color: colorScheme.primary,
      ),
    );

    if (hasPoster) {
      posterBox = Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            posterUrl,
            width: 48,
            height: 70,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 48,
              height: 70,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.movie_outlined, color: colorScheme.primary),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasPoster)
            GestureDetector(
              onTap: () => openFullScreenImage(
                context,
                imageUrl: posterUrl,
                heroTag: heroTag,
                title: review.title,
                subtitle: review.detail,
              ),
              child: posterBox,
            )
          else
            posterBox,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMovie ? 'Reseña de película' : 'Reseña de música',
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  review.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (review.detail != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    review.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 4),
                RatingStars(stars: review.stars, size: 15),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<String> images, ColorScheme colorScheme) {
    if (images.isEmpty) return const SizedBox.shrink();

    if (images.length == 1) {
      return GestureDetector(
        onTap: () => openFullScreenImage(
          context,
          imageUrl: images[0],
          imageUrls: images,
          initialIndex: 0,
          heroTag: 'post-image-${widget.post.id}-0',
        ),
        child: Hero(
          tag: 'post-image-${widget.post.id}-0',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 380),
              width: double.infinity,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: _buildNetworkImage(images[0], colorScheme),
            ),
          ),
        ),
      );
    }

    if (images.length == 2) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildGridItem(images, 0, colorScheme)),
              const SizedBox(width: 4),
              Expanded(child: _buildGridItem(images, 1, colorScheme)),
            ],
          ),
        ),
      );
    }

    if (images.length == 3) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 260,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _buildGridItem(images, 0, colorScheme)),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildGridItem(images, 1, colorScheme)),
                    const SizedBox(height: 4),
                    Expanded(child: _buildGridItem(images, 2, colorScheme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 4 or more images: 2x2 grid
    final extraCount = images.length - 4;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 280,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildGridItem(images, 0, colorScheme)),
                  const SizedBox(height: 4),
                  Expanded(child: _buildGridItem(images, 1, colorScheme)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildGridItem(images, 2, colorScheme)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildGridItem(images, 3, colorScheme),
                        if (extraCount > 0)
                          GestureDetector(
                            onTap: () => openFullScreenImage(
                              context,
                              imageUrls: images,
                              initialIndex: 3,
                              heroTag: 'post-image-${widget.post.id}-3',
                            ),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.65),
                              alignment: Alignment.center,
                              child: Text(
                                '+$extraCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(List<String> images, int index, ColorScheme colorScheme) {
    final url = images[index];
    final heroTag = 'post-image-${widget.post.id}-$index';
    return GestureDetector(
      onTap: () => openFullScreenImage(
        context,
        imageUrls: images,
        initialIndex: index,
        heroTag: heroTag,
      ),
      child: Hero(
        tag: heroTag,
        child: Container(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: _buildNetworkImage(url, colorScheme),
        ),
      ),
    );
  }

  Widget _buildNetworkImage(String url, ColorScheme colorScheme) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
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
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_rounded, color: colorScheme.outline),
      ),
    );
  }
}
