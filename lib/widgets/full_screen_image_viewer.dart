import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens a photo in a full-screen viewer with a fade + Hero transition.
///
/// Pass [imageUrl], [imageUrls] (with [initialIndex]) or [image]
/// (an image already in memory, e.g. `MemoryImage(decryptedBytes)`).
///
/// If the image is already on screen as a thumbnail decoded with
/// `cacheWidth: thumbnailCacheWidth`, pass that width so the viewer can show
/// the cached thumbnail while the full-resolution image loads.
Future<void> openFullScreenImage(
  BuildContext context, {
  String? imageUrl,
  List<String>? imageUrls,
  int initialIndex = 0,
  ImageProvider? image,
  required Object heroTag,
  int? thumbnailCacheWidth,
  String? title,
  String? subtitle,
}) {
  final resolvedList = (imageUrls != null && imageUrls.isNotEmpty)
      ? imageUrls
      : (imageUrl != null && imageUrl.isNotEmpty ? [imageUrl] : const <String>[]);

  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => FullScreenImageViewer(
        imageUrl: imageUrl,
        imageUrls: resolvedList,
        initialIndex: initialIndex.clamp(0, resolvedList.isEmpty ? 0 : resolvedList.length - 1),
        image: image,
        heroTag: heroTag,
        thumbnailCacheWidth: thumbnailCacheWidth,
        title: title,
        subtitle: subtitle,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Instagram-style photo viewer: black background, pinch or double-tap to
/// zoom, drag down/up (when not zoomed) or press Esc to close.
class FullScreenImageViewer extends StatefulWidget {
  final String? imageUrl;
  final List<String> imageUrls;
  final int initialIndex;
  final ImageProvider? image;
  final Object heroTag;
  final int? thumbnailCacheWidth;
  final String? title;
  final String? subtitle;

  const FullScreenImageViewer({
    super.key,
    this.imageUrl,
    this.imageUrls = const [],
    this.initialIndex = 0,
    this.image,
    required this.heroTag,
    this.thumbnailCacheWidth,
    this.title,
    this.subtitle,
  }) : assert(
          (imageUrl == null && identical(imageUrls, const <String>[])) != (image == null),
          'Pass exactly one of imageUrl or image',
        );

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  static const double _dismissDistance = 120;
  static const double _doubleTapScale = 2.5;

  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  double _dragOffset = 0;
  bool _isZoomed = false;

  late int _currentIndex = widget.initialIndex;
  late final PageController _pageController = PageController(initialPage: widget.initialIndex);

  List<String> get _urls => widget.imageUrls.isNotEmpty
      ? widget.imageUrls
      : (widget.imageUrl != null && widget.imageUrl!.isNotEmpty ? [widget.imageUrl!] : const []);

  @override
  void dispose() {
    _transformController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  ImageProvider _providerFor(int index) {
    if (widget.image != null) return widget.image!;
    final urls = _urls;
    if (index >= 0 && index < urls.length) {
      return NetworkImage(urls[index]);
    }
    return NetworkImage(widget.imageUrl ?? '');
  }

  ImageProvider get _imageProvider => _providerFor(_currentIndex);

  void _close() => Navigator.of(context).maybePop();

  void _updateZoomState() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _transformController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformController.value = Matrix4.identity()
        ..translateByDouble(
          -position.dx * (_doubleTapScale - 1),
          -position.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _updateZoomState();
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    if (_isZoomed || details.pointerCount > 1) return;
    setState(() => _dragOffset += details.focalPointDelta.dy);
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    _updateZoomState();
    if (_isZoomed) return;
    final flung = details.velocity.pixelsPerSecond.dy.abs() > 900;
    if (_dragOffset.abs() > _dismissDistance || flung) {
      _close();
    } else if (_dragOffset != 0) {
      setState(() => _dragOffset = 0);
    }
  }

  Widget _buildPlaceholder([int? index]) {
    final width = widget.thumbnailCacheWidth;
    final provider = index != null ? _providerFor(index) : _imageProvider;
    if (width == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Image(
          image: ResizeImage(provider, width: width),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        const CircularProgressIndicator(color: Colors.white),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundOpacity = (1.0 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);
    final chromeOpacity = (1.0 - (_dragOffset.abs() / 80)).clamp(0.0, 1.0);
    final hasMultiple = _urls.length > 1;

    final String? subtitleText;
    if (hasMultiple) {
      final countText = '${_currentIndex + 1} de ${_urls.length}';
      subtitleText = widget.subtitle != null ? '${widget.subtitle} · $countText' : countText;
    } else {
      subtitleText = widget.subtitle;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        if (hasMultiple) ...{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            if (_currentIndex < _urls.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          },
        },
      },
      child: Focus(
        autofocus: true,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Material(
            color: Colors.black.withValues(alpha: backgroundOpacity),
            child: Stack(
              children: [
                Positioned.fill(
                  child: hasMultiple
                      ? PageView.builder(
                          controller: _pageController,
                          physics: _isZoomed
                              ? const NeverScrollableScrollPhysics()
                              : const BouncingScrollPhysics(),
                          itemCount: _urls.length,
                          onPageChanged: (i) {
                            setState(() {
                              _currentIndex = i;
                              _transformController.value = Matrix4.identity();
                              _isZoomed = false;
                            });
                          },
                          itemBuilder: (context, i) {
                            return GestureDetector(
                              onDoubleTapDown: (details) => _doubleTapDetails = details,
                              onDoubleTap: _handleDoubleTap,
                              child: InteractiveViewer(
                                transformationController: _currentIndex == i ? _transformController : null,
                                minScale: 1,
                                maxScale: 5,
                                panEnabled: _isZoomed,
                                onInteractionUpdate: _handleInteractionUpdate,
                                onInteractionEnd: _handleInteractionEnd,
                                child: Transform.translate(
                                  offset: Offset(0, _dragOffset),
                                  child: Center(
                                    child: Image(
                                      image: _providerFor(i),
                                      fit: BoxFit.contain,
                                      loadingBuilder: (context, child, progress) =>
                                          progress == null ? child : _buildPlaceholder(i),
                                      errorBuilder: (_, _, _) => const Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.broken_image_rounded, color: Colors.white70, size: 48),
                                          SizedBox(height: 8),
                                          Text(
                                            'No se pudo cargar la imagen',
                                            style: TextStyle(color: Colors.white70),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : GestureDetector(
                          onDoubleTapDown: (details) => _doubleTapDetails = details,
                          onDoubleTap: _handleDoubleTap,
                          child: InteractiveViewer(
                            transformationController: _transformController,
                            minScale: 1,
                            maxScale: 5,
                            panEnabled: _isZoomed,
                            onInteractionUpdate: _handleInteractionUpdate,
                            onInteractionEnd: _handleInteractionEnd,
                            child: Transform.translate(
                              offset: Offset(0, _dragOffset),
                              child: Center(
                                child: Hero(
                                  tag: widget.heroTag,
                                  child: Image(
                                    image: _imageProvider,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child, progress) =>
                                        progress == null ? child : _buildPlaceholder(),
                                    errorBuilder: (_, _, _) => const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image_rounded, color: Colors.white70, size: 48),
                                        SizedBox(height: 8),
                                        Text(
                                          'No se pudo cargar la imagen',
                                          style: TextStyle(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),

                // Desktop Prev/Next Buttons
                if (hasMultiple) ...[
                  if (_currentIndex > 0)
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          },
                        ),
                      ),
                    ),
                  if (_currentIndex < _urls.length - 1)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_forward_ios_rounded),
                          onPressed: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          },
                        ),
                      ),
                    ),
                ],

                // Top bar: close button + optional sender/time and photo counter
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: chromeOpacity == 0,
                    child: AnimatedOpacity(
                      opacity: chromeOpacity,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 16, 16),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Cerrar',
                                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                                  onPressed: _close,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.title != null)
                                        Text(
                                          widget.title!,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      if (subtitleText != null)
                                        Text(
                                          subtitleText,
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
