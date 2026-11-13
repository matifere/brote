import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class GiphyItem {
  final String id;
  final String title;
  final String previewUrl;
  final String originalUrl;
  final double? width;
  final double? height;

  const GiphyItem({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.originalUrl,
    this.width,
    this.height,
  });

  factory GiphyItem.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>? ?? {};
    final fixedHeight = images['fixed_height'] as Map<String, dynamic>? ?? {};
    final original = images['original'] as Map<String, dynamic>? ?? {};
    final downsized = images['downsized'] as Map<String, dynamic>? ?? {};

    final preview = fixedHeight['url'] as String? ??
        downsized['url'] as String? ??
        original['url'] as String? ??
        '';

    final orig = original['url'] as String? ??
        downsized['url'] as String? ??
        preview;

    final w = double.tryParse(fixedHeight['width']?.toString() ?? '');
    final h = double.tryParse(fixedHeight['height']?.toString() ?? '');

    return GiphyItem(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      previewUrl: preview,
      originalUrl: orig,
      width: w,
      height: h,
    );
  }
}

class GiphyService {
  static const String directGiphyApiKey = String.fromEnvironment('GIPHY_API_KEY');
  static const String _giphyDirectBaseUrl = 'api.giphy.com';

  final String? apiKey;
  final http.Client? client;

  GiphyService({this.apiKey, this.client});

  String get _effectiveApiKey => (apiKey != null && apiKey!.isNotEmpty)
      ? apiKey!
      : directGiphyApiKey;

  Future<List<GiphyItem>> getTrending({int limit = 30, int offset = 0}) async {
    Uri uri;
    if (_effectiveApiKey.isNotEmpty) {
      uri = Uri.https(_giphyDirectBaseUrl, '/v1/gifs/trending', {
        'api_key': _effectiveApiKey,
        'limit': '$limit',
        'offset': '$offset',
        'rating': 'g',
      });
    } else {
      final backend = AuthService().baseUrl;
      uri = Uri.parse('$backend/api/gifs/trending?limit=$limit&offset=$offset');
    }
    return _fetch(uri);
  }

  Future<List<GiphyItem>> search(String query, {int limit = 30, int offset = 0}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getTrending(limit: limit, offset: offset);
    }
    Uri uri;
    if (_effectiveApiKey.isNotEmpty) {
      uri = Uri.https(_giphyDirectBaseUrl, '/v1/gifs/search', {
        'api_key': _effectiveApiKey,
        'q': trimmed,
        'limit': '$limit',
        'offset': '$offset',
        'rating': 'g',
        'lang': 'es',
      });
    } else {
      final backend = AuthService().baseUrl;
      uri = Uri.parse('$backend/api/gifs/search?q=${Uri.encodeComponent(trimmed)}&limit=$limit&offset=$offset');
    }
    return _fetch(uri);
  }

  Future<List<GiphyItem>> _fetch(Uri uri) async {
    try {
      final res = client != null
          ? await client!.get(uri)
          : await http.get(uri);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = decoded['data'] as List<dynamic>? ?? [];
        return data
            .whereType<Map<String, dynamic>>()
            .map((item) => GiphyItem.fromJson(item))
            .where((item) => item.originalUrl.isNotEmpty && item.previewUrl.isNotEmpty)
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('GiphyService fetch error: $e');
      return [];
    }
  }
}
