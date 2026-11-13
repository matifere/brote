import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:brote/models/post_item.dart';
import 'package:brote/services/media_optimizer.dart';
import 'package:brote/services/video_cache_service.dart';
import 'package:brote/widgets/post_card.dart';
import 'package:brote/widgets/post_video_player.dart';
import 'package:brote/screens/create_post_screen.dart';
import 'package:brote/widgets/full_screen_media_feed_viewer.dart';

void main() {
  group('MediaOptimizer Image & Video optimization', () {
    test('downscales large images and compresses to JPEG', () async {
      // Create a simulated 2000x1500 raw image in memory
      final rawImage = img.Image(width: 2000, height: 1500);
      for (var y = 0; y < 1500; y += 10) {
        for (var x = 0; x < 2000; x += 10) {
          rawImage.setPixelRgba(x, y, 200, 100, 50, 255);
        }
      }
      final pngBytes = Uint8List.fromList(img.encodePng(rawImage));

      final optimized = await MediaOptimizer.optimizeImage(
        pngBytes,
        filename: 'heavy_camera_photo.png',
        maxWidth: 1280,
        maxHeight: 1280,
        quality: 75,
      );

      // 2000x1500 scaled down to fit 1280x1280 preserving aspect ratio -> 1280x960
      expect(optimized.width, 1280);
      expect(optimized.height, 960);
      expect(optimized.mimeType, 'image/jpeg');
      expect(optimized.filename, 'heavy_camera_photo.jpg');
      expect(optimized.bytes.isNotEmpty, true);
    });

    test('enforces video size limits to optimize storage', () async {
      // 26 MB video should exceed the 25 MB limit
      final oversizedBytes = Uint8List(26 * 1024 * 1024);

      expect(
        () => MediaOptimizer.optimizeVideo(
          rawBytes: oversizedBytes,
          filename: 'heavy_video.mp4',
        ),
        throwsA(isA<MediaOptimizationException>()),
      );

      // 5 MB video within limit
      final normalBytes = Uint8List(5 * 1024 * 1024);
      final result = await MediaOptimizer.optimizeVideo(
        rawBytes: normalBytes,
        filename: 'good_clip.mp4',
      );
      expect(result.optimizedSize, normalBytes.length);
      expect(result.mimeType, 'video/mp4');
    });

    test('accepts localFilePath and returns video metadata', () async {
      // Test video optimization fallback with bytes
      final sampleBytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      final result = await MediaOptimizer.optimizeVideo(
        rawBytes: sampleBytes,
        filename: 'clip.mp4',
      );
      expect(result.bytes.length, 1024);
      expect(result.mimeType, 'video/mp4');
      expect(result.filename, 'clip.mp4');
    });
  });

  group('PostItem videoUrl support', () {
    test('parses videoUrl from json', () {
      final json = {
        'id': 'post-123',
        'authorId': 'u1',
        'authorName': 'Mati',
        'authorUsername': 'mati',
        'content': 'Mirá este video',
        'videoUrl': 'https://example.com/api/posts/media/video-123.mp4',
      };

      final post = PostItem.fromJson(json);
      expect(post.videoUrl, 'https://example.com/api/posts/media/video-123.mp4');
    });

    test('parses snake_case video_url from json', () {
      final json = {
        'id': 'post-456',
        'author_id': 'u2',
        'author_name': 'Ana',
        'author_username': 'ana',
        'content': 'Otro video',
        'video_url': 'https://example.com/api/posts/media/video-456.mp4',
      };

      final post = PostItem.fromJson(json);
      expect(post.videoUrl, 'https://example.com/api/posts/media/video-456.mp4');
    });
  });

  group('PostCard & Video Player widget rendering', () {
    testWidgets('renders PostVideoPlayer when post has videoUrl', (tester) async {
      final post = PostItem(
        id: 'post-video-1',
        authorId: 'u1',
        authorName: 'Mati',
        authorUsername: 'mati',
        content: 'Check out this video clip!',
        videoUrl: 'https://example.com/videos/sample.mp4',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(post: post),
          ),
        ),
      );

      expect(find.byType(PostVideoPlayer), findsOneWidget);
      expect(find.text('Check out this video clip!'), findsOneWidget);
      // Autoplays automatically: no "Tocar para reproducir" button is rendered!
      expect(find.text('Tocar para reproducir'), findsNothing);
      // Videos are muted by default
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    });

    testWidgets('displays sensitive blur overlay on sensitive video post', (tester) async {
      final post = PostItem(
        id: 'post-video-sensitive',
        authorId: 'u1',
        authorName: 'Mati',
        authorUsername: 'mati',
        content: 'Sensitive video',
        videoUrl: 'https://example.com/videos/sensitive.mp4',
        isSensitive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(post: post),
          ),
        ),
      );

      expect(find.text('Video con contenido sensible'), findsOneWidget);
      expect(find.text('Ver video'), findsOneWidget);

      // Tapping "Ver video" unblurs the video
      await tester.tap(find.text('Ver video'));
      await tester.pumpAndSettle();

      expect(find.text('Video con contenido sensible'), findsNothing);
    });

    testWidgets('CreatePostScreen displays Video attachment button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CreatePostScreen(),
          ),
        ),
      );

      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Agregar foto'), findsOneWidget);
    });
  });

  group('FullScreenMediaFeedViewer (TikTok/Instagram style fullscreen scroll)', () {
    testWidgets('renders fullscreen media viewer with post overlay and vertical swipe', (tester) async {
      final post1 = PostItem(
        id: 'post-media-1',
        authorId: 'u1',
        authorName: 'Mati',
        authorUsername: 'mati',
        content: 'Primer video increíble',
        videoUrl: 'https://example.com/video1.mp4',
        likesCount: 15,
        commentsCount: 3,
      );

      final post2 = PostItem(
        id: 'post-media-2',
        authorId: 'u2',
        authorName: 'Ana',
        authorUsername: 'ana',
        content: 'Segunda foto genial',
        imageUrl: 'https://example.com/photo2.jpg',
        likesCount: 42,
        commentsCount: 7,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FullScreenMediaFeedViewer(
              initialPost: post1,
              contextPosts: [post1, post2],
            ),
          ),
        ),
      );

      // Verify counter pill displays "1 de 2"
      expect(find.text('1 de 2'), findsOneWidget);
      // Verify author name and username
      expect(find.text('Mati'), findsOneWidget);
      expect(find.textContaining('@mati'), findsOneWidget);
      expect(find.text('Primer video increíble'), findsOneWidget);
      // Verify actions
      expect(find.text('15'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Compartir'), findsOneWidget);

      // Swipe up vertically to go to the next post
      await tester.fling(find.byType(PageView).first, const Offset(0, -400), 1000);
      await tester.pumpAndSettle();

      // Verify second post is now shown with counter "2 de 2"
      expect(find.text('2 de 2'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.textContaining('@ana'), findsOneWidget);
      expect(find.text('Segunda foto genial'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('PostCard renders expand button on video player', (tester) async {
      final post = PostItem(
        id: 'post-video-expand',
        authorId: 'u1',
        authorName: 'Mati',
        authorUsername: 'mati',
        content: 'Video con botón expandir',
        videoUrl: 'https://example.com/video.mp4',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(post: post),
          ),
        ),
      );

      expect(find.text('Expandir'), findsOneWidget);
    });

    testWidgets('FullScreenMediaFeedViewer renders description and review badge', (tester) async {
      final reviewPost = PostItem(
        id: 'post-review-media',
        authorId: 'u3',
        authorName: 'Mati',
        authorUsername: 'mati',
        content: '🎬 Inception (2010) ★★★★★\n\nObra maestra absoluta de Christopher Nolan',
        videoUrl: 'https://example.com/inception.mp4',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FullScreenMediaFeedViewer(
              initialPost: reviewPost,
              contextPosts: [reviewPost],
            ),
          ),
        ),
      );

      // Verify review title and stars
      expect(find.text('Inception'), findsOneWidget);
      expect(find.text(' 5'), findsOneWidget);
      // Verify caption/description text is rendered
      expect(find.text('Obra maestra absoluta de Christopher Nolan'), findsOneWidget);
    });
  });

  group('VideoCacheService disk caching & fast path', () {
    test('returns null when video is not yet cached locally', () {
      final cached = VideoCacheService.instance.getCachedPathIfAvailable('https://example.com/not_cached.mp4');
      expect(cached, isNull);
    });

    test('getCachedPathOrOriginal returns original URL when not cached', () {
      const url = 'https://example.com/stream_video.mp4';
      final path = VideoCacheService.instance.getCachedPathOrOriginal(url);
      expect(path, url);
    });

    test('preload returns a Future resolving to string safely', () async {
      const url = 'https://example.com/preload_video.mp4';
      final result = await VideoCacheService.instance.preload(url);
      expect(result, isNotEmpty);
    });
  });
}
