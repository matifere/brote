import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/rating.dart';

/// A movie, song or album found in a public catalog.
class CatalogItem {
  final RatingCategory category;
  final String title;
  final int? year;
  final String? artist;
  final String? subtitle;
  final String? imageUrl;

  const CatalogItem({
    required this.category,
    required this.title,
    this.year,
    this.artist,
    this.subtitle,
    this.imageUrl,
  });

  RatedItem toRating([int stars = 1]) => RatedItem.create(
        category: category,
        title: title,
        year: year,
        artist: artist,
        stars: stars,
      );
}

/// Which kind of music to search for; null searches both.
enum MusicKind { song, album }

/// Searches movies on Wikidata and music on the iTunes Search API.
/// Both are public, need no API key and allow browser (CORS) requests.
class CatalogService {
  static final CatalogService _instance = CatalogService._internal();
  factory CatalogService() => _instance;
  CatalogService._internal();

  static const String _wikidataEndpoint = 'https://www.wikidata.org/w/api.php';
  static const String _itunesEndpoint = 'https://itunes.apple.com/search';

  /// Restricts results to films: feature, animated feature, animated, documentary and short films.
  static const String _filmFilter =
      'haswbstatement:P31=Q11424|P31=Q29168811|P31=Q202866|P31=Q93204|P31=Q24869';

  static final RegExp _yearPattern = RegExp(r'\b(1[89]\d{2}|20\d{2})\b');

  /// Store edition tags that only lengthen titles, e.g. "(Remastered)" or " - Single".
  static final RegExp _editionTag = RegExp(
    r'\s*[\(\[][^\)\]]*(remaster|deluxe|edition|edición|anniversary|aniversario|expanded|bonus)[^\)\]]*[\)\]]'
    r'|\s+-\s+(single|ep|remaster(ed)?( \d{4})?)$',
    caseSensitive: false,
  );

  /// Drops store edition tags, e.g. "Abbey Road (Remastered)" becomes "Abbey Road".
  static String cleanMusicTitle(String title) => title.replaceAll(_editionTag, '').trim();

  Map<String, String> get _headers => {
        if (!kIsWeb) 'User-Agent': 'Brote/0.1 (https://github.com/matifere/brote)',
      };

  /// Returns null when the catalog can't be reached.
  Future<List<CatalogItem>?> search(RatingCategory category, String query, {MusicKind? musicKind}) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return Future.value([]);
    return switch (category) {
      RatingCategory.movie => _searchMovies(cleanQuery),
      RatingCategory.music => _searchMusic(cleanQuery, musicKind),
    };
  }

  Future<List<CatalogItem>?> _searchMovies(String query) async {
    try {
      final searchUri = Uri.parse(_wikidataEndpoint).replace(queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': '$query $_filmFilter',
        'srlimit': '15',
        'srprop': '',
        'format': 'json',
        'formatversion': '2',
        'origin': '*',
      });
      final searchResponse = await http.get(searchUri, headers: _headers).timeout(const Duration(seconds: 10));
      if (searchResponse.statusCode != 200) return null;

      final hits = (jsonDecode(searchResponse.body)['query']?['search'] as List?) ?? [];
      final ids = hits.map((hit) => hit['title'] as String).toList();
      if (ids.isEmpty) return [];

      final entitiesUri = Uri.parse(_wikidataEndpoint).replace(queryParameters: {
        'action': 'wbgetentities',
        'ids': ids.join('|'),
        'props': 'labels|descriptions',
        'languages': 'es',
        'languagefallback': '1',
        'format': 'json',
        'origin': '*',
      });
      final entitiesResponse = await http.get(entitiesUri, headers: _headers).timeout(const Duration(seconds: 10));
      if (entitiesResponse.statusCode != 200) return null;

      final entities = (jsonDecode(entitiesResponse.body)['entities'] as Map<String, dynamic>?) ?? {};
      final results = <CatalogItem>[];
      for (final id in ids) {
        final entity = entities[id] as Map<String, dynamic>?;
        final title = entity?['labels']?['es']?['value'] as String?;
        if (title == null || title.trim().isEmpty) continue;

        final description = entity?['descriptions']?['es']?['value'] as String?;
        final yearMatch = description != null ? _yearPattern.firstMatch(description) : null;
        results.add(CatalogItem(
          category: RatingCategory.movie,
          title: title.trim(),
          year: yearMatch != null ? int.parse(yearMatch.group(1)!) : null,
          subtitle: description,
        ));
      }
      return results;
    } catch (e) {
      debugPrint('Error searching movies: $e');
      return null;
    }
  }

  Future<List<CatalogItem>?> _searchMusic(String query, MusicKind? kind) async {
    if (kind != null) {
      final rows = await _itunesSearch(query, entity: kind == MusicKind.song ? 'song' : 'album', limit: 25);
      return rows == null ? null : _toMusicItems(rows);
    }

    final responses = await Future.wait([
      _itunesSearch(query, entity: 'song', limit: 20),
      _itunesSearch(query, entity: 'album', limit: 6),
    ]);
    if (responses.every((r) => r == null)) return null;

    final songs = _toMusicItems(responses[0] ?? []);
    final albums = _toMusicItems(responses[1] ?? []);
    // Album search also returns covers and singles named like a song, so the
    // best songs go first, then a few albums, then the remaining songs.
    // The "Álbumes" filter shows every album match.
    return [...songs.take(5), ...albums.take(4), ...songs.skip(5)];
  }

  List<CatalogItem> _toMusicItems(List<Map<String, dynamic>> rows) {
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final row in rows) {
      final isAlbum = row['wrapperType'] == 'collection';
      final rawTitle = (isAlbum ? row['collectionName'] : row['trackName']) as String?;
      final artist = (row['artistName'] as String?)?.trim();
      if (rawTitle == null || artist == null) continue;

      final title = cleanMusicTitle(rawTitle);
      // The same song shows up in several albums and compilations
      if (!seen.add('${title.toLowerCase()}|${artist.toLowerCase()}')) continue;

      final year = int.tryParse((row['releaseDate'] as String? ?? '').split('-').first);
      final collection = row['collectionName'] as String?;
      final album = collection != null ? cleanMusicTitle(collection) : null;
      items.add(CatalogItem(
        category: RatingCategory.music,
        title: title,
        artist: artist,
        year: year,
        subtitle: isAlbum
            ? '$artist · Álbum${year != null ? ' · $year' : ''}'
            : '$artist · Tema${album != null && album.isNotEmpty ? ' · $album' : ''}',
        imageUrl: (row['artworkUrl100'] as String?)?.replaceFirst('100x100bb', '200x200bb'),
      ));
    }
    return items;
  }

  Future<List<Map<String, dynamic>>?> _itunesSearch(String query, {required String entity, required int limit}) async {
    try {
      final uri = Uri.parse(_itunesEndpoint).replace(queryParameters: {
        'term': query,
        'media': 'music',
        'entity': entity,
        'limit': '$limit',
        'country': 'AR',
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final rows = (jsonDecode(response.body)['results'] as List?) ?? [];
      return rows.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error searching music ($entity): $e');
      return null;
    }
  }
}
