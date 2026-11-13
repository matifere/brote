import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/video_cache_service.dart';

class PostVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isSensitive;
  final double aspectRatio;
  final bool autoPlay;
  final bool initialMuted;
  final VoidCallback? onFullScreenRequested;

  const PostVideoPlayer({
    super.key,
    required this.videoUrl,
    this.isSensitive = false,
    this.aspectRatio = 16 / 9,
    this.autoPlay = true,
    this.initialMuted = true,
    this.onFullScreenRequested,
  });

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> {
  Player? _player;
  VideoController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  late bool _isMuted;
  bool _hasError = false;
  bool _revealedSensitive = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool get _isTestEnvironment =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _isMuted = widget.initialMuted;
    _revealedSensitive = !widget.isSensitive;
    if (widget.autoPlay && _revealedSensitive) {
      _initPlayer();
    }
  }

  @override
  void didUpdateWidget(covariant PostVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl) {
      _player?.dispose();
      _player = null;
      _controller = null;
      _isInitialized = false;
      _isPlaying = false;
      if (widget.autoPlay && _revealedSensitive) {
        _initPlayer();
      }
    }
  }

  Future<void> _initPlayer() async {
    if (_isTestEnvironment) {
      setState(() {
        _isInitialized = true;
        _isPlaying = true;
      });
      return;
    }

    if (_player != null) return;

    try {
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

      await player.setPlaylistMode(PlaylistMode.loop);

      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });

      player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      player.stream.error.listen((err) {
        debugPrint('PostVideoPlayer error: $err');
        if (mounted) setState(() => _hasError = true);
      });

      player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      });

      final cachedPath = VideoCacheService.instance.getCachedPathIfAvailable(widget.videoUrl);
      final mediaSource = cachedPath ?? widget.videoUrl;
      if (cachedPath == null) {
        VideoCacheService.instance.preload(widget.videoUrl);
      }

      await player.setVolume(_isMuted ? 0.0 : 100.0);

      await player.open(Media(mediaSource), play: widget.autoPlay);

      if (mounted) {
        setState(() {
          _player = player;
          _controller = controller;
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('Error starting video player: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_isInitialized) {
      _initPlayer();
      return;
    }
    _player?.playOrPause();
  }

  void _toggleMute() {
    if (_player == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _player!.setVolume(_isMuted ? 0.0 : 100.0);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Aspect ratio container
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 460),
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video surface or placeholder
              if (_isInitialized)
                if (_controller != null)
                  Video(
                    controller: _controller!,
                    controls: NoVideoControls,
                  )
                else
                  Container(
                    key: const ValueKey('video_surface_test'),
                    color: Colors.black,
                  )
              else
                _buildPlaceholder(colorScheme),

              // Tap surface to toggle playback
              if (_revealedSensitive && !_hasError)
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _togglePlayPause,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),

              // Central play/pause overlay button (only shown when explicitly paused by user)
              if (_isInitialized && _revealedSensitive && !_hasError)
                Center(
                  child: IgnorePointer(
                    ignoring: _isPlaying,
                    child: AnimatedOpacity(
                      opacity: _isPlaying ? 0.0 : 0.9,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          iconSize: 42,
                          color: Colors.white,
                          icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                    ),
                  ),
                ),

              // Top buffering bar (slow network feedback)
              if (_isBuffering && _revealedSensitive && !_hasError)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),

              // Bottom control bar (progress, time, mute)
              if (_isInitialized && _revealedSensitive && !_hasError)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Small play/pause
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                        const SizedBox(width: 4),

                        // Time position / duration
                        Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Slider progress bar
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              activeTrackColor: colorScheme.primary,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: colorScheme.primary,
                            ),
                            child: Slider(
                              value: _duration.inMilliseconds > 0
                                  ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                  : 0.0,
                              onChanged: (val) {
                                final target = Duration(
                                  milliseconds: (val * _duration.inMilliseconds).round(),
                                );
                                _player?.seek(target);
                              },
                            ),
                          ),
                        ),

                        // Mute button
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(
                            _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _toggleMute,
                        ),
                        if (widget.onFullScreenRequested != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(
                              Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            tooltip: 'Pantalla completa',
                            onPressed: widget.onFullScreenRequested,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Top-right fullscreen expand button
              if (widget.onFullScreenRequested != null && _revealedSensitive)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: widget.onFullScreenRequested,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24, width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Expandir',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Error display
              if (_hasError)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent, size: 32),
                        const SizedBox(height: 8),
                        const Text(
                          'No se pudo reproducir el video',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _hasError = false);
                            _initPlayer();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),

              // Sensitive overlay
              if (!_revealedSensitive)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.85),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.visibility_off_rounded, color: Colors.amber, size: 38),
                        const SizedBox(height: 10),
                        const Text(
                          'Video con contenido sensible',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Esta publicación fue marcada como sensible.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          onPressed: () {
                            setState(() => _revealedSensitive = true);
                            _initPlayer();
                          },
                          icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
                          label: const Text('Ver video'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF202026),
            Color(0xFF141418),
            Color(0xFF0D0D10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 1.2),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                size: 28,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
