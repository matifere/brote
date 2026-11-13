import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/post_item.dart';
import '../models/rating.dart';
import '../models/user_profile.dart';
import '../screens/profile_screen.dart';
import '../services/auth_service.dart';
import '../services/video_cache_service.dart';
import 'post_comments_sheet.dart';

/// Opens an immersive fullscreen media viewer with smooth vertical scroll
/// between media posts (videos & images), just like TikTok, X, and Instagram.
Future<void> openFullScreenMediaFeed(
  BuildContext context, {
  required PostItem initialPost,
  List<PostItem>? contextPosts,
  int initialMediaIndex = 0,
  ValueChanged<PostItem>? onPostUpdated,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => FullScreenMediaFeedViewer(
        initialPost: initialPost,
        contextPosts: contextPosts,
        initialMediaIndex: initialMediaIndex,
        onPostUpdated: onPostUpdated,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class FullScreenMediaFeedViewer extends StatefulWidget {
  final PostItem initialPost;
  final List<PostItem>? contextPosts;
  final int initialMediaIndex;
  final ValueChanged<PostItem>? onPostUpdated;

  const FullScreenMediaFeedViewer({
    super.key,
    required this.initialPost,
    this.contextPosts,
    this.initialMediaIndex = 0,
    this.onPostUpdated,
  });

  @override
  State<FullScreenMediaFeedViewer> createState() => _FullScreenMediaFeedViewerState();
}

class _FullScreenMediaFeedViewerState extends State<FullScreenMediaFeedViewer> {
  late final List<PostItem> _mediaPosts;
  late int _currentIndex;
  late final PageController _verticalController;

  bool _isGlobalMuted = true;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    final all = (widget.contextPosts != null && widget.contextPosts!.isNotEmpty)
        ? widget.contextPosts!
        : [widget.initialPost];

    // Filter posts that have either a video or at least one image
    _mediaPosts = all.where((p) {
      final hasVideo = p.videoUrl != null && p.videoUrl!.isNotEmpty;
      final hasImages = p.imageUrls.isNotEmpty || (p.imageUrl != null && p.imageUrl!.isNotEmpty);
      return hasVideo || hasImages;
    }).toList();

    // Ensure the tapped post is present in the list
    if (!_mediaPosts.any((p) => p.id == widget.initialPost.id)) {
      _mediaPosts.insert(0, widget.initialPost);
    }

    final foundIndex = _mediaPosts.indexWhere((p) => p.id == widget.initialPost.id);
    _currentIndex = foundIndex >= 0 ? foundIndex : 0;
    _verticalController = PageController(initialPage: _currentIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAdjacentPosts(_currentIndex);
    });
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  /// Precache photos, posters, avatars, and videos of surrounding posts in advance
  void _precacheAdjacentPosts(int centerIndex) {
    if (!mounted) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    for (int offset in [-1, 0, 1, 2, 3]) {
      final idx = centerIndex + offset;
      if (idx >= 0 && idx < _mediaPosts.length) {
        final p = _mediaPosts[idx];
        // Aggressively download adjacent videos directly to local NVMe/SSD cache
        if (p.videoUrl != null && p.videoUrl!.isNotEmpty) {
          VideoCacheService.instance.preload(p.videoUrl!);
        }
        for (final url in p.imageUrls) {
          if (url.isNotEmpty) {
            precacheImage(NetworkImage(url), context, onError: (_, _) {}).catchError((_) {});
          }
        }
        if (p.imageUrl != null && p.imageUrl!.isNotEmpty) {
          precacheImage(NetworkImage(p.imageUrl!), context, onError: (_, _) {}).catchError((_) {});
        }
        if (p.authorAvatarUrl != null && p.authorAvatarUrl!.isNotEmpty) {
          precacheImage(NetworkImage(p.authorAvatarUrl!), context, onError: (_, _) {}).catchError((_) {});
        }
      }
    }
  }

  void _nextPost() {
    if (_currentIndex < _mediaPosts.length - 1) {
      _verticalController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _prevPost() {
    if (_currentIndex > 0) {
      _verticalController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _toggleGlobalMute() {
    setState(() => _isGlobalMuted = !_isGlobalMuted);
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = _currentIndex < _mediaPosts.length - 1;
    final hasPrev = _currentIndex > 0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowDown): _nextPost,
        const SingleActivator(LogicalKeyboardKey.arrowUp): _prevPost,
        const SingleActivator(LogicalKeyboardKey.pageDown): _nextPost,
        const SingleActivator(LogicalKeyboardKey.pageUp): _prevPost,
        const SingleActivator(LogicalKeyboardKey.keyJ): _nextPost,
        const SingleActivator(LogicalKeyboardKey.keyK): _prevPost,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleGlobalMute,
      },
      child: Focus(
        autofocus: true,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                // Vertical Media Feed (swiping between posts)
                PageView.builder(
                  controller: _verticalController,
                  scrollDirection: Axis.vertical,
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  itemCount: _mediaPosts.length,
                  onPageChanged: (i) {
                    setState(() {
                      _currentIndex = i;
                      _isZoomed = false;
                    });
                    _precacheAdjacentPosts(i);
                  },
                  itemBuilder: (context, index) {
                    final post = _mediaPosts[index];
                    final isActive = index == _currentIndex;
                    final isPreload = (index - _currentIndex).abs() <= 1;

                    return _MediaFeedPostItem(
                      key: ValueKey('media_post_${post.id}'),
                      post: post,
                      isActive: isActive,
                      isPreload: isPreload,
                      isMuted: _isGlobalMuted,
                      initialMediaIndex: (index == _currentIndex) ? widget.initialMediaIndex : 0,
                      onToggleMute: _toggleGlobalMute,
                      onZoomChanged: (z) => setState(() => _isZoomed = z),
                      onPostUpdated: widget.onPostUpdated,
                      onNextPost: hasNext ? _nextPost : null,
                      onPrevPost: hasPrev ? _prevPost : null,
                      onClose: _close,
                      currentIndex: index,
                      totalCount: _mediaPosts.length,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaFeedPostItem extends StatefulWidget {
  final PostItem post;
  final bool isActive;
  final bool isPreload;
  final bool isMuted;
  final int initialMediaIndex;
  final VoidCallback onToggleMute;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<PostItem>? onPostUpdated;
  final VoidCallback? onNextPost;
  final VoidCallback? onPrevPost;
  final VoidCallback onClose;
  final int currentIndex;
  final int totalCount;

  const _MediaFeedPostItem({
    super.key,
    required this.post,
    required this.isActive,
    required this.isPreload,
    required this.isMuted,
    required this.initialMediaIndex,
    required this.onToggleMute,
    required this.onZoomChanged,
    this.onPostUpdated,
    this.onNextPost,
    this.onPrevPost,
    required this.onClose,
    required this.currentIndex,
    required this.totalCount,
  });

  @override
  State<_MediaFeedPostItem> createState() => _MediaFeedPostItemState();
}

class _MediaFeedPostItemState extends State<_MediaFeedPostItem> with SingleTickerProviderStateMixin {
  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  bool _isTextExpanded = false;
  bool _revealedSensitive = false;

  // Double tap heart animation
  late final AnimationController _heartAnimController;
  late final Animation<double> _heartScaleAnim;
  late final Animation<double> _heartOpacityAnim;
  bool _showHeartAnimation = false;

  bool get _hasVideo => widget.post.videoUrl != null && widget.post.videoUrl!.isNotEmpty;

  List<String> get _images {
    if (widget.post.imageUrls.isNotEmpty) return widget.post.imageUrls;
    if (widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty) {
      return [widget.post.imageUrl!];
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
    _commentsCount = widget.post.commentsCount;
    _revealedSensitive = !widget.post.isSensitive;

    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _heartScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.25).chain(CurveTween(curve: Curves.easeOutBack)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeIn)), weight: 40),
    ]).animate(_heartAnimController);

    _heartOpacityAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartAnimController);

    _heartAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _showHeartAnimation = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _MediaFeedPostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post.id != oldWidget.post.id) {
      setState(() {
        _isLiked = widget.post.isLiked;
        _likesCount = widget.post.likesCount;
        _commentsCount = widget.post.commentsCount;
        _revealedSensitive = !widget.post.isSensitive;
      });
    }
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    super.dispose();
  }

  void _triggerDoubleTapLike() {
    setState(() => _showHeartAnimation = true);
    _heartAnimController.forward(from: 0.0);
    if (!_isLiked) {
      _toggleLike();
    }
  }

  Future<void> _toggleLike() async {
    final prevLiked = _isLiked;
    final prevCount = _likesCount;

    setState(() {
      _isLiked = !prevLiked;
      _likesCount = prevLiked ? (prevCount - 1).clamp(0, 999999) : prevCount + 1;
    });

    widget.post.isLiked = _isLiked;
    widget.post.likesCount = _likesCount;
    widget.onPostUpdated?.call(widget.post);

    final res = await AuthService().toggleLikePost(widget.post.id);
    if (!mounted) return;

    if (res == null) {
      // Revert if error
      setState(() {
        _isLiked = prevLiked;
        _likesCount = prevCount;
      });
      widget.post.isLiked = prevLiked;
      widget.post.likesCount = prevCount;
      widget.onPostUpdated?.call(widget.post);
    } else {
      setState(() {
        _isLiked = res['isLiked'] as bool;
        _likesCount = res['likesCount'] as int;
      });
      widget.post.isLiked = _isLiked;
      widget.post.likesCount = _likesCount;
      widget.onPostUpdated?.call(widget.post);
    }
  }

  void _openComments() {
    showPostCommentsSheet(
      context,
      widget.post,
      onCommentsChanged: () {
        if (!mounted) return;
        setState(() {
          _commentsCount = widget.post.commentsCount;
        });
        widget.onPostUpdated?.call(widget.post);
      },
    );
  }

  void _copyPostLink() {
    final text = widget.post.content;
    final url = widget.post.videoUrl ?? widget.post.imageUrl ?? '';
    final full = [if (text.isNotEmpty) text, if (url.isNotEmpty) url].join('\n\n');
    Clipboard.setData(ClipboardData(text: full));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado al portapapeles'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 700;

    // Resolve post caption text: use parsed body if non-empty, or full content as fallback
    final rawBody = widget.post.parsedContent.body.trim();
    final rawContent = widget.post.content.trim();
    final captionText = rawBody.isNotEmpty
        ? rawBody
        : (widget.post.parsedContent.review == null ? rawContent : '');

    return Stack(
      fit: StackFit.expand,
      children: [
        // Media Content (Video with preloading or Image carousel)
        GestureDetector(
          onDoubleTap: _triggerDoubleTapLike,
          behavior: HitTestBehavior.opaque,
          child: _hasVideo
              ? _FullScreenVideoView(
                  videoUrl: widget.post.videoUrl!,
                  posterUrl: widget.post.imageUrl,
                  isActive: widget.isActive,
                  isPreload: widget.isPreload,
                  isMuted: widget.isMuted,
                  isSensitive: widget.post.isSensitive && !_revealedSensitive,
                  onRevealSensitive: () => setState(() => _revealedSensitive = true),
                  onDoubleTapLike: _triggerDoubleTapLike,
                )
              : _FullScreenImagesView(
                  images: _images,
                  initialIndex: widget.initialMediaIndex,
                  onZoomChanged: widget.onZoomChanged,
                  isSensitive: widget.post.isSensitive && !_revealedSensitive,
                  onRevealSensitive: () => setState(() => _revealedSensitive = true),
                ),
        ),

        // Double-Tap Animated Heart Popup
        if (_showHeartAnimation)
          Center(
            child: ScaleTransition(
              scale: _heartScaleAnim,
              child: FadeTransition(
                opacity: _heartOpacityAnim,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.redAccent,
                    size: 96,
                  ),
                ),
              ),
            ),
          ),

        // Top Vignette Gradient Overlay
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom Vignette Gradient Overlay (re-enforced for clear readability over bright videos)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 250,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Top Navigation Bar
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Close button
              GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),

              // Page counter pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12, width: 0.8),
                ),
                child: Text(
                  '${widget.currentIndex + 1} de ${widget.totalCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Sound toggle (if video)
              if (_hasVideo)
                GestureDetector(
                  onTap: widget.onToggleMute,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                )
              else
                const SizedBox(width: 38),
            ],
          ),
        ),

        // Right Action Bar (TikTok / X / Instagram style)
        Positioned(
          right: 14,
          bottom: 50,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Like Button
              _ActionButton(
                icon: _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _isLiked ? Colors.redAccent : Colors.white,
                label: '$_likesCount',
                onTap: _toggleLike,
              ),
              const SizedBox(height: 18),

              // Comments Button
              _ActionButton(
                icon: Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                label: '$_commentsCount',
                onTap: _openComments,
              ),
              const SizedBox(height: 18),

              // Share Button
              _ActionButton(
                icon: Icons.share_outlined,
                color: Colors.white,
                label: 'Compartir',
                onTap: _copyPostLink,
              ),

              // Desktop navigation arrows (Up / Down)
              if (isDesktop) ...[
                const SizedBox(height: 24),
                if (widget.onPrevPost != null) ...[
                  _ActionButton(
                    icon: Icons.keyboard_arrow_up_rounded,
                    color: Colors.white70,
                    label: 'Ant.',
                    size: 28,
                    onTap: widget.onPrevPost!,
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.onNextPost != null) ...[
                  _ActionButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    label: 'Sig.',
                    size: 28,
                    onTap: widget.onNextPost!,
                  ),
                ],
              ],
            ],
          ),
        ),

        // Bottom Left Post Author & Caption Info Overlay
        // Positioned clearly above the video scrubber line with SafeArea support
        Positioned(
          left: 16,
          right: 90, // reserve space for right action column
          bottom: 38,
          child: SafeArea(
            top: false,
            bottom: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Author row: Avatar + Name + Username + Time
                GestureDetector(
                  onTap: () {
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
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundImage: (widget.post.authorAvatarUrl != null &&
                                widget.post.authorAvatarUrl!.isNotEmpty)
                            ? NetworkImage(widget.post.authorAvatarUrl!)
                            : null,
                        child: (widget.post.authorAvatarUrl == null ||
                                widget.post.authorAvatarUrl!.isEmpty)
                            ? Text(
                                widget.post.authorName.isNotEmpty
                                    ? widget.post.authorName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.post.authorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(color: Colors.black, blurRadius: 8),
                                        Shadow(color: Colors.black87, blurRadius: 4),
                                      ],
                                    ),
                                  ),
                                ),
                                if (widget.post.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified_rounded, size: 14, color: Colors.lightBlueAccent),
                                ],
                              ],
                            ),
                            Text(
                              '@${widget.post.authorUsername} · ${widget.post.timeAgo}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 8),
                                  Shadow(color: Colors.black87, blurRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Review chip badge if available
                if (widget.post.parsedContent.review != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.7), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.post.parsedContent.review!.category == RatingCategory.movie
                              ? Icons.movie_outlined
                              : Icons.music_note_rounded,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.post.parsedContent.review!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                        Text(
                          ' ${widget.post.parsedContent.review!.stars}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Post Description / Caption Text with high-contrast background card
                if (captionText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: _isTextExpanded ? 260 : 70,
                          ),
                          child: SingleChildScrollView(
                            physics: _isTextExpanded
                                ? const BouncingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            child: MarkdownBody(
                              data: captionText,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  height: 1.35,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                                strong: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                code: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  backgroundColor: Colors.black87,
                                  color: Colors.lightGreenAccent.shade200,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (captionText.length > 80 || captionText.contains('\n'))
                          GestureDetector(
                            onTap: () => setState(() => _isTextExpanded = !_isTextExpanded),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _isTextExpanded ? 'Ver menos' : 'más...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final double size;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: size),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen video player with media_kit, background preloading, and smooth poster fallback
class _FullScreenVideoView extends StatefulWidget {
  final String videoUrl;
  final String? posterUrl;
  final bool isActive;
  final bool isPreload;
  final bool isMuted;
  final bool isSensitive;
  final VoidCallback onRevealSensitive;
  final VoidCallback onDoubleTapLike;

  const _FullScreenVideoView({
    required this.videoUrl,
    this.posterUrl,
    required this.isActive,
    required this.isPreload,
    required this.isMuted,
    required this.isSensitive,
    required this.onRevealSensitive,
    required this.onDoubleTapLike,
  });

  @override
  State<_FullScreenVideoView> createState() => _FullScreenVideoViewState();
}

class _FullScreenVideoViewState extends State<_FullScreenVideoView> {
  Player? _player;
  VideoController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasRenderedFrame = false;
  bool _isBuffering = false;
  double _bufferingPercentage = 0.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _showPlayPauseIndicator = false;

  bool get _isTestEnvironment =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if ((widget.isActive || widget.isPreload) && !widget.isSensitive) {
      _initPlayer(playOnOpen: widget.isActive);
    }
  }

  @override
  void didUpdateWidget(covariant _FullScreenVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSensitive) return;

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        if (!_isInitialized) {
          _initPlayer(playOnOpen: true);
        } else {
          _player?.setVolume(widget.isMuted ? 0.0 : 100.0);
          _player?.play();
        }
      } else {
        _player?.pause();
      }
    } else if (widget.isPreload && !oldWidget.isPreload && !_isInitialized) {
      // Background buffer preload when post enters adjacent range
      _initPlayer(playOnOpen: false);
    } else if (!widget.isPreload && !widget.isActive && _isInitialized) {
      // Reclaim memory if user scrolled far away
      _disposePlayer();
    }

    if (widget.isMuted != oldWidget.isMuted) {
      _player?.setVolume(widget.isMuted ? 0.0 : 100.0);
    }
  }

  Future<void> _initPlayer({required bool playOnOpen}) async {
    if (_isTestEnvironment) {
      setState(() {
        _isInitialized = true;
        _isPlaying = playOnOpen;
        _hasRenderedFrame = true;
        _isBuffering = false;
      });
      return;
    }

    if (_player != null) {
      if (playOnOpen && !_isPlaying) {
        _player?.setVolume(widget.isMuted ? 0.0 : 100.0);
        _player?.play();
      }
      return;
    }

    try {
      final cachedPath = VideoCacheService.instance.getCachedPathIfAvailable(widget.videoUrl);
      final mediaSource = cachedPath ?? widget.videoUrl;
      if (cachedPath == null) {
        VideoCacheService.instance.preload(widget.videoUrl);
      }

      final player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
        ),
      );
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );

      player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
            if (playing) _hasRenderedFrame = true;
          });
        }
      });

      player.stream.position.listen((pos) {
        if (mounted) {
          setState(() {
            _position = pos;
            if (pos > Duration.zero) _hasRenderedFrame = true;
          });
        }
      });

      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      });

      player.stream.bufferingPercentage.listen((pct) {
        if (mounted) setState(() => _bufferingPercentage = pct);
      });

      await player.setPlaylistMode(PlaylistMode.loop);

      // Mute while in background preloading; restore if active
      player.setVolume((playOnOpen && !widget.isMuted) ? 100.0 : 0.0);

      // Open media: if playOnOpen is false, connects and buffers first frame into memory cache
      await player.open(Media(mediaSource), play: playOnOpen);

      if (mounted) {
        setState(() {
          _player = player;
          _controller = controller;
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading full screen video: $e');
    }
  }

  void _disposePlayer() {
    _player?.dispose();
    _player = null;
    _controller = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _isPlaying = false;
        _hasRenderedFrame = false;
        _isBuffering = false;
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_isInitialized) {
      _initPlayer(playOnOpen: true);
      return;
    }
    _player?.playOrPause();
    setState(() => _showPlayPauseIndicator = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showPlayPauseIndicator = false);
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildPosterOrPlaceholder() {
    if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty) {
      return Image.network(
        widget.posterUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _buildGradientPlaceholder(),
      );
    }
    return _buildGradientPlaceholder();
  }

  Widget _buildGradientPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF222228),
            Color(0xFF16161B),
            Color(0xFF0D0D10),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12, width: 1.5),
          ),
          child: const Icon(
            Icons.videocam_rounded,
            size: 38,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSensitive) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_off_rounded, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Video con contenido sensible',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta publicación fue marcada como sensible.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  widget.onRevealSensitive();
                  _initPlayer(playOnOpen: true);
                },
                icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
                label: const Text('Ver video'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        // 1. Poster / Gradient placeholder underneath: NO BLACK SCREEN EVER!
        Positioned.fill(
          child: _buildPosterOrPlaceholder(),
        ),

        // 2. Video render surface with smooth fade-in
        if (_isInitialized && _controller != null)
          AnimatedOpacity(
            opacity: _hasRenderedFrame ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Center(
              child: Video(
                controller: _controller!,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
          ),

        // 3. Tap surface to toggle play/pause
        Positioned.fill(
          child: GestureDetector(
            onTap: _togglePlayPause,
            onDoubleTap: widget.onDoubleTapLike,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),

        // 4. Animated play/pause central icon
        if (_showPlayPauseIndicator)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 54,
                color: Colors.white,
              ),
            ),
          ),

        // 5. Bottom Scrubber Bar (Progress & Duration)
        if (_isInitialized && _duration.inMilliseconds > 0)
          Positioned(
            left: 14,
            right: 14,
            bottom: 6,
            child: Row(
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0),
                      onChanged: (val) {
                        final target = Duration(
                          milliseconds: (val * _duration.inMilliseconds).round(),
                        );
                        _player?.seek(target);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),

        // 6. Top Glowing Loading & Buffering Bar (shown when loading or buffering over slow connection)
        if (widget.isActive && (!_hasRenderedFrame || _isBuffering))
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 3.5,
              child: LinearProgressIndicator(
                value: (_bufferingPercentage > 0 && _bufferingPercentage < 100)
                    ? _bufferingPercentage / 100.0
                    : null,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),

        // 7. Center Loading Card & Progress Bar (shown when waiting for buffer or on slow connection)
        if (widget.isActive && (!_hasRenderedFrame || _isBuffering))
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 0.8),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 2),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _bufferingPercentage > 0
                            ? 'Cargando video (${_bufferingPercentage.toInt()}%)...'
                            : 'Cargando video...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 150,
                      height: 4,
                      child: LinearProgressIndicator(
                        value: (_bufferingPercentage > 0 && _bufferingPercentage < 100)
                            ? _bufferingPercentage / 100.0
                            : null,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Fullscreen images view with horizontal carousel and pinch-to-zoom
class _FullScreenImagesView extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final ValueChanged<bool> onZoomChanged;
  final bool isSensitive;
  final VoidCallback onRevealSensitive;

  const _FullScreenImagesView({
    required this.images,
    required this.initialIndex,
    required this.onZoomChanged,
    required this.isSensitive,
    required this.onRevealSensitive,
  });

  @override
  State<_FullScreenImagesView> createState() => _FullScreenImagesViewState();
}

class _FullScreenImagesViewState extends State<_FullScreenImagesView> {
  late final PageController _horizontalController;
  late int _imageIndex;
  final TransformationController _transformController = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _imageIndex = widget.initialIndex.clamp(0, widget.images.isEmpty ? 0 : widget.images.length - 1);
    _horizontalController = PageController(initialPage: _imageIndex);
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _onScaleChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSensitive) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_off_rounded, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Imagen con contenido sensible',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta publicación fue marcada como sensible.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: widget.onRevealSensitive,
                icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
                label: const Text('Ver imagen'),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.images.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
      );
    }

    final hasMultiple = widget.images.length > 1;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Horizontal PageView for multi-image posts
        PageView.builder(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          physics: _isZoomed
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          itemCount: widget.images.length,
          onPageChanged: (i) {
            setState(() {
              _imageIndex = i;
              _transformController.value = Matrix4.identity();
              _isZoomed = false;
            });
            widget.onZoomChanged(false);
          },
          itemBuilder: (context, index) {
            final url = widget.images[index];

            return InteractiveViewer(
              transformationController: _imageIndex == index ? _transformController : null,
              minScale: 1.0,
              maxScale: 4.0,
              onInteractionUpdate: (_) => _onScaleChanged(),
              onInteractionEnd: (_) => _onScaleChanged(),
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        ),
                  errorBuilder: (_, _, _) => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                      SizedBox(height: 8),
                      Text(
                        'No se pudo cargar la imagen',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // Dots indicator if multiple images
        if (hasMultiple)
          Positioned(
            top: MediaQuery.of(context).padding.top + 52,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.images.length, (i) {
                final isCurrent = i == _imageIndex;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isCurrent ? 14 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isCurrent ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
