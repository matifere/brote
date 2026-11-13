import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// High-performance local disk cache & aggressive preloader for video playback.
/// Eliminates network latency on repeated views, feed-to-fullscreen transitions,
/// and preloads adjacent videos for instant 0ms playback.
class VideoCacheService {
  VideoCacheService._();
  static final VideoCacheService instance = VideoCacheService._();

  static const int maxCacheSizeBytes = 250 * 1024 * 1024; // 250 MB

  final Map<String, Future<String>> _activeDownloads = {};
  final ValueNotifier<Map<String, double>> downloadProgress = ValueNotifier({});

  bool get _isSupportedPlatform =>
      !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  Directory get _cacheDir =>
      Directory('${Directory.systemTemp.path}/brote_video_cache');

  String _cacheKey(String url) {
    final hash = url.hashCode.abs().toRadixString(16);
    // Sanitize end of url for identifiable extension
    final cleanUrl = url.split('?').first;
    final ext = cleanUrl.endsWith('.mp4')
        ? '.mp4'
        : (cleanUrl.endsWith('.webm') ? '.webm' : '.mp4');
    return 'brote_vid_$hash$ext';
  }

  File _targetFile(String url) {
    return File('${_cacheDir.path}/${_cacheKey(url)}');
  }

  File _markerFile(String url) {
    return File('${_cacheDir.path}/${_cacheKey(url)}.done');
  }

  File _tempFile(String url) {
    return File('${_cacheDir.path}/${_cacheKey(url)}.tmp');
  }

  /// Returns the local file path if already fully cached on disk, otherwise null.
  String? getCachedPathIfAvailable(String url) {
    if (!_isSupportedPlatform || url.isEmpty || url.startsWith('file://') || url.startsWith('/')) {
      return null;
    }
    try {
      final target = _targetFile(url);
      final marker = _markerFile(url);
      if (target.existsSync() && marker.existsSync() && target.lengthSync() > 0) {
        return target.path;
      }
    } catch (_) {}
    return null;
  }

  /// Returns the local cached path if available, or the original URL immediately.
  String getCachedPathOrOriginal(String url) {
    return getCachedPathIfAvailable(url) ?? url;
  }

  /// Aggressively preloads and caches the video to local storage in background.
  /// Returns the local file path once cached, or the original url if download fails.
  Future<String> preload(String url) {
    if (!_isSupportedPlatform || url.isEmpty || url.startsWith('file://') || url.startsWith('/')) {
      return Future.value(url);
    }

    // Fast hit: already on disk
    final cached = getCachedPathIfAvailable(url);
    if (cached != null) {
      return Future.value(cached);
    }

    // In-flight download hit
    if (_activeDownloads.containsKey(url)) {
      return _activeDownloads[url]!;
    }

    final future = _downloadVideo(url);
    _activeDownloads[url] = future;
    return future;
  }

  Future<String> _downloadVideo(String url) async {
    try {
      final dir = _cacheDir;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final target = _targetFile(url);
      final marker = _markerFile(url);
      final temp = _tempFile(url);

      if (await target.exists() && await marker.exists() && await target.length() > 0) {
        return target.path;
      }

      final uri = Uri.tryParse(url);
      if (uri == null) return url;

      final request = http.Request('GET', uri);
      final client = http.Client();
      final response = await client.send(request);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final contentLength = response.contentLength ?? 0;
        int downloaded = 0;

        final sink = temp.openWrite();
        await response.stream.listen(
          (chunk) {
            sink.add(chunk);
            downloaded += chunk.length;
            if (contentLength > 0) {
              final pct = (downloaded / contentLength).clamp(0.0, 1.0);
              final current = Map<String, double>.from(downloadProgress.value);
              current[url] = pct;
              downloadProgress.value = current;
            }
          },
          cancelOnError: true,
        ).asFuture();

        await sink.flush();
        await sink.close();

        // Atomically rename to target and mark complete
        if (await temp.exists()) {
          if (await target.exists()) {
            await target.delete();
          }
          await temp.rename(target.path);
          await marker.writeAsString('ok');

          // Clean up progress entry
          final current = Map<String, double>.from(downloadProgress.value);
          current.remove(url);
          downloadProgress.value = current;

          // Prune old videos if total cache exceeded
          _pruneCacheIfNeeded();

          return target.path;
        }
      }
    } catch (e) {
      debugPrint('VideoCacheService download error for $url: $e');
      try {
        final temp = _tempFile(url);
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    } finally {
      _activeDownloads.remove(url);
    }
    return url;
  }

  /// Prune oldest cached video files if cache size exceeds limit
  Future<void> _pruneCacheIfNeeded() async {
    try {
      final dir = _cacheDir;
      if (!await dir.exists()) return;

      final entities = await dir.list().toList();
      int totalBytes = 0;
      final videoFiles = <File>[];

      for (final e in entities) {
        if (e is File && !e.path.endsWith('.tmp') && !e.path.endsWith('.done')) {
          totalBytes += await e.length();
          videoFiles.add(e);
        }
      }

      if (totalBytes > maxCacheSizeBytes) {
        // Sort by last accessed / last modified ascending
        videoFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        for (final f in videoFiles) {
          if (totalBytes <= maxCacheSizeBytes * 0.75) break;
          final len = await f.length();
          await f.delete();
          final marker = File('${f.path}.done');
          if (await marker.exists()) await marker.delete();
          totalBytes -= len;
        }
      }
    } catch (_) {}
  }
}
