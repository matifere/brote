import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Result of an image or video optimization operation.
class OptimizedMediaResult {
  final Uint8List bytes;
  final int originalSize;
  final int optimizedSize;
  final int? width;
  final int? height;
  final String mimeType;
  final String filename;
  final String? localFilePath;
  final Uint8List? thumbnailBytes;

  const OptimizedMediaResult({
    required this.bytes,
    required this.originalSize,
    required this.optimizedSize,
    this.width,
    this.height,
    required this.mimeType,
    required this.filename,
    this.localFilePath,
    this.thumbnailBytes,
  });

  /// Percentage of space saved, e.g. 75.4%
  double get savingsPercentage {
    if (originalSize <= 0) return 0.0;
    final saved = originalSize - optimizedSize;
    if (saved <= 0) return 0.0;
    return (saved / originalSize) * 100.0;
  }

  String get summary {
    final origMb = (originalSize / (1024 * 1024)).toStringAsFixed(2);
    final optMb = (optimizedSize / (1024 * 1024)).toStringAsFixed(2);
    return 'Optimizado: $origMb MB -> $optMb MB (${savingsPercentage.toStringAsFixed(1)}% de ahorro)';
  }
}

class MediaOptimizationException implements Exception {
  final String message;
  const MediaOptimizationException(this.message);

  @override
  String toString() => message;
}

class MediaOptimizer {
  static const int maxVideoBytes = 25 * 1024 * 1024; // 25 MB
  static const int maxImageBytes = 12 * 1024 * 1024; // 12 MB raw limit before optimization
  static const int targetImageDimension = 1280; // Max width/height for standard social feeds
  static const int targetImageQuality = 78; // High visual quality, ~80% space reduction

  /// Optimizes an image: downscales if larger than [maxWidth]/[maxHeight],
  /// compresses to JPEG with [quality], and strips heavy EXIF metadata.
  static Future<OptimizedMediaResult> optimizeImage(
    Uint8List rawBytes, {
    String filename = 'image.jpg',
    int maxWidth = targetImageDimension,
    int maxHeight = targetImageDimension,
    int quality = targetImageQuality,
  }) async {
    final originalSize = rawBytes.length;

    try {
      // Decode the image (handles PNG, JPEG, WEBP, GIF, BMP)
      final decoded = await compute(_decodeImageInIsolate, rawBytes);
      if (decoded == null) {
        // Fallback: If decode fails, make sure it's within raw limits
        if (originalSize > maxImageBytes) {
          throw const MediaOptimizationException(
            'La imagen es demasiado pesada y no se pudo procesar. El límite máximo es de 12 MB.',
          );
        }
        return OptimizedMediaResult(
          bytes: rawBytes,
          originalSize: originalSize,
          optimizedSize: originalSize,
          mimeType: 'image/jpeg',
          filename: filename,
        );
      }

      var width = decoded.width;
      var height = decoded.height;

      img.Image processed = decoded;

      // Downscale if exceeds dimensions preserving aspect ratio
      if (width > maxWidth || height > maxHeight) {
        if (width >= height) {
          final newWidth = maxWidth;
          final newHeight = ((height * maxWidth) / width).round();
          processed = img.copyResize(decoded, width: newWidth, height: newHeight, interpolation: img.Interpolation.linear);
        } else {
          final newHeight = maxHeight;
          final newWidth = ((width * maxHeight) / height).round();
          processed = img.copyResize(decoded, width: newWidth, height: newHeight, interpolation: img.Interpolation.linear);
        }
        width = processed.width;
        height = processed.height;
      }

      // Encode to optimized JPEG with quality compression
      final compressedBytes = Uint8List.fromList(img.encodeJpg(processed, quality: quality));

      // Choose cleaner filename
      final base = filename.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final cleanFilename = '$base.jpg';

      debugPrint('MediaOptimizer: Original ${originalSize ~/ 1024} KB -> Optimizado ${compressedBytes.length ~/ 1024} KB');

      return OptimizedMediaResult(
        bytes: compressedBytes,
        originalSize: originalSize,
        optimizedSize: compressedBytes.length,
        width: width,
        height: height,
        mimeType: 'image/jpeg',
        filename: cleanFilename,
      );
    } catch (e) {
      if (e is MediaOptimizationException) rethrow;
      debugPrint('MediaOptimizer error optimizing image: $e');
      if (originalSize > maxImageBytes) {
        throw const MediaOptimizationException(
          'La imagen supera el límite máximo permitido de 12 MB.',
        );
      }
      return OptimizedMediaResult(
        bytes: rawBytes,
        originalSize: originalSize,
        optimizedSize: originalSize,
        mimeType: 'image/jpeg',
        filename: filename,
      );
    }
  }

  /// Internal decode helper suitable for isolate compute
  static img.Image? _decodeImageInIsolate(Uint8List bytes) {
    return img.decodeImage(bytes);
  }

  /// Validates and optimizes a video.
  /// On desktop platforms where ffmpeg is present, transcodes to 720p 30fps crf 26 faststart mp4
  /// and extracts a thumbnail frame for instant preview.
  /// Enforces maximum file size limit ([maxVideoBytes], 25MB) to save cloud storage.
  static Future<OptimizedMediaResult> optimizeVideo({
    Uint8List? rawBytes,
    String? localFilePath,
    String filename = 'video.mp4',
  }) async {
    int originalSize = rawBytes?.length ?? 0;
    if (originalSize == 0 && localFilePath != null && !kIsWeb) {
      try {
        final f = File(localFilePath);
        if (await f.exists()) originalSize = await f.length();
      } catch (_) {}
    }

    Uint8List? thumbBytes;

    // Check if ffmpeg is available on desktop for fast compression and thumbnail extraction
    if (!kIsWeb && localFilePath != null && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      try {
        // Extract thumbnail in parallel / fast
        thumbBytes = await _extractThumbnailWithFfmpeg(localFilePath);

        final compResult = await _compressVideoWithFfmpeg(localFilePath, filename);
        if (compResult != null) {
          final compressedBytes = compResult.bytes;
          if (compressedBytes.length > maxVideoBytes) {
            throw MediaOptimizationException(
              'El video comprimido sigue superando el límite de 25 MB (${(compressedBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). Por favor, recortá la duración.',
            );
          }
          return OptimizedMediaResult(
            bytes: compressedBytes,
            originalSize: originalSize > 0 ? originalSize : compressedBytes.length,
            optimizedSize: compressedBytes.length,
            mimeType: 'video/mp4',
            filename: filename.endsWith('.mp4') ? filename : '$filename.mp4',
            localFilePath: compResult.outputPath,
            thumbnailBytes: thumbBytes,
          );
        }
      } catch (e) {
        if (e is MediaOptimizationException) rethrow;
        debugPrint('MediaOptimizer ffmpeg compression fallback: $e');
      }
    }

    // Direct fallback if ffmpeg is not present
    final finalBytes = rawBytes ?? (localFilePath != null ? await File(localFilePath).readAsBytes() : Uint8List(0));
    final finalSize = finalBytes.length;

    // Direct size check
    if (finalSize > maxVideoBytes) {
      final mb = (finalSize / (1024 * 1024)).toStringAsFixed(1);
      throw MediaOptimizationException(
        'El video es demasiado pesado ($mb MB). El límite máximo es de 25 MB para cuidar el almacenamiento. Por favor, recortalo a menos de 60 segundos o reducí la calidad.',
      );
    }

    return OptimizedMediaResult(
      bytes: finalBytes,
      originalSize: originalSize > 0 ? originalSize : finalSize,
      optimizedSize: finalSize,
      mimeType: filename.endsWith('.webm') ? 'video/webm' : 'video/mp4',
      filename: filename,
      localFilePath: localFilePath,
      thumbnailBytes: thumbBytes,
    );
  }

  /// Compress video using system ffmpeg with fast 720p/30fps settings
  static Future<({Uint8List bytes, String outputPath})?> _compressVideoWithFfmpeg(String inputPath, String filename) async {
    try {
      final tempDir = Directory.systemTemp;
      final outPath = '${tempDir.path}/opt_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final res = await Process.run('ffmpeg', [
        '-y',
        '-i',
        inputPath,
        '-t',
        '60', // Cap at max 60s
        '-vf',
        "scale='min(720,iw)':-2", // 720p max width, preserves aspect ratio
        '-r',
        '30', // Cap at 30 fps for bandwidth efficiency
        '-c:v',
        'libx264',
        '-crf',
        '26', // High visual quality, compact file size
        '-maxrate',
        '1800k',
        '-bufsize',
        '3000k',
        '-preset',
        'veryfast', // Ultra fast transcode
        '-c:a',
        'aac',
        '-b:a',
        '96k',
        '-ar',
        '44100',
        '-movflags',
        '+faststart', // Web streaming ready
        outPath,
      ]);

      if (res.exitCode == 0) {
        final outFile = File(outPath);
        if (await outFile.exists()) {
          final bytes = await outFile.readAsBytes();
          return (bytes: bytes, outputPath: outPath);
        }
      }
    } catch (e) {
      debugPrint('ffmpeg execution failed: $e');
    }
    return null;
  }

  /// Fast video frame thumbnail extraction with ffmpeg
  static Future<Uint8List?> _extractThumbnailWithFfmpeg(String inputPath) async {
    try {
      final tempDir = Directory.systemTemp;
      final thumbPath = '${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final res = await Process.run('ffmpeg', [
        '-y',
        '-ss',
        '00:00:00.5',
        '-i',
        inputPath,
        '-vframes',
        '1',
        '-vf',
        "scale='min(640,iw)':-2",
        '-q:v',
        '3',
        thumbPath,
      ]);
      if (res.exitCode == 0) {
        final f = File(thumbPath);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          try {
            await f.delete();
          } catch (_) {}
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('ffmpeg thumbnail extraction failed: $e');
    }
    return null;
  }
}
