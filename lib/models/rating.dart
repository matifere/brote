/// What a rating is about. Each category is stored as its own line in the bio.
enum RatingCategory {
  movie(prefix: '🎬 ', noun: 'películas'),
  music(prefix: '🎵 ', noun: 'música');

  const RatingCategory({required this.prefix, required this.noun});

  final String prefix;
  final String noun;
}

/// A movie, song or album rated by the user (1 to 5 stars).
///
/// Ratings live inside the profile bio, one line per category, e.g.
/// `🎬 Relatos salvajes (2014) ★★★★★ · Dune (2021) ★★★★☆`
/// `🎵 Abbey Road — The Beatles ★★★★★`
/// so they are saved through the existing profile endpoint and stay readable
/// as plain text. Review posts reuse the same encoding as their first line.
class RatedItem {
  static const int maxTitleLength = 40;
  static const int maxArtistLength = 30;

  final RatingCategory category;
  final String title;

  /// Release year, only stored for movies.
  final int? year;

  /// Performer, only stored for music.
  final String? artist;
  final int stars;

  const RatedItem({
    required this.category,
    required this.title,
    this.year,
    this.artist,
    required this.stars,
  });

  /// Builds a rating from free-form data, cleaning the text so it can be
  /// stored safely in the bio line.
  factory RatedItem.create({
    required RatingCategory category,
    required String title,
    int? year,
    String? artist,
    int stars = 1,
  }) {
    final cleanArtist = artist == null ? '' : _clean(artist, maxArtistLength);
    return RatedItem(
      category: category,
      title: _clean(title, maxTitleLength),
      year: category == RatingCategory.movie ? year : null,
      artist: category == RatingCategory.music && cleanArtist.isNotEmpty ? cleanArtist : null,
      stars: stars.clamp(1, 5),
    );
  }

  static final RegExp _moviePattern = RegExp(r'^(.+?)(?: \((\d{4})\))? ([★☆]{5})$');
  static final RegExp _musicPattern = RegExp(r'^(.+?)(?: — (.+?))? ([★☆]{5})$');

  /// Removes characters reserved by the bio format and shortens long values.
  static String _clean(String value, int maxLength) {
    var clean = value.replaceAll(RegExp('[·—]'), '-').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length > maxLength) {
      clean = '${clean.substring(0, maxLength - 1).trimRight()}…';
    }
    return clean;
  }

  /// Whether both refer to the same movie, song or album, ignoring the stars.
  bool sameAs(RatedItem other) =>
      category == other.category &&
      title.toLowerCase() == other.title.toLowerCase() &&
      year == other.year &&
      artist?.toLowerCase() == other.artist?.toLowerCase();

  RatedItem withStars(int newStars) => RatedItem(
        category: category,
        title: title,
        year: year,
        artist: artist,
        stars: newStars.clamp(1, 5),
      );

  /// The year for movies or the artist for music.
  String? get detail => category == RatingCategory.movie ? year?.toString() : artist;

  String encode() {
    final detailPart = switch (category) {
      RatingCategory.movie => year != null ? ' ($year)' : '',
      RatingCategory.music => artist != null ? ' — $artist' : '',
    };
    return '$title$detailPart ${'★' * stars}${'☆' * (5 - stars)}';
  }

  static RatedItem? decode(RatingCategory category, String entry) {
    final pattern = category == RatingCategory.movie ? _moviePattern : _musicPattern;
    final match = pattern.firstMatch(entry.trim());
    if (match == null) return null;
    final stars = '★'.allMatches(match.group(3)!).length;
    if (stars < 1) return null;
    return RatedItem(
      category: category,
      title: match.group(1)!,
      year: category == RatingCategory.movie ? int.tryParse(match.group(2) ?? '') : null,
      artist: category == RatingCategory.music ? match.group(2) : null,
      stars: stars,
    );
  }

  /// A single rating with its category prefix, as used in review posts.
  String encodeLine() => '${category.prefix}${encode()}';

  static RatedItem? decodeLine(String line) {
    final trimmed = line.trim();
    for (final category in RatingCategory.values) {
      if (trimmed.startsWith(category.prefix)) {
        return decode(category, trimmed.substring(category.prefix.length));
      }
    }
    return null;
  }
}

/// A profile bio split into the free text the user wrote and their ratings.
class ProfileBio {
  static const int maxLength = 300;
  static const String separator = ' · ';

  final String text;

  /// All ratings, most recent first within each category.
  final List<RatedItem> ratings;

  const ProfileBio({this.text = '', this.ratings = const []});

  factory ProfileBio.parse(String? bio) {
    if (bio == null || bio.trim().isEmpty) return const ProfileBio();

    // Rating lines sit at the end of the bio, one per category
    final lines = bio.trimRight().split('\n');
    final parsed = <RatingCategory, List<RatedItem>>{};
    while (lines.isNotEmpty) {
      final line = lines.last.trim();
      final category = RatingCategory.values
          .where((c) => line.startsWith(c.prefix) && !parsed.containsKey(c))
          .firstOrNull;
      if (category == null) break;

      final items = line
          .substring(category.prefix.length)
          .split(separator)
          .map((entry) => RatedItem.decode(category, entry))
          .whereType<RatedItem>()
          .toList();
      if (items.isEmpty) break;

      parsed[category] = items;
      lines.removeLast();
    }

    if (parsed.isEmpty) return ProfileBio(text: bio.trim());
    return ProfileBio(
      text: lines.join('\n').trim(),
      ratings: [for (final category in RatingCategory.values) ...?parsed[category]],
    );
  }

  List<RatedItem> of(RatingCategory category) => ratings.where((r) => r.category == category).toList();

  String get ratingsBlock => [
        for (final category in RatingCategory.values)
          if (of(category).isNotEmpty)
            '${category.prefix}${of(category).map((r) => r.encode()).join(separator)}',
      ].join('\n');

  /// Characters left for the free text once the ratings are reserved.
  int get maxTextLength {
    final block = ratingsBlock;
    return block.isEmpty ? maxLength : maxLength - block.length - 2;
  }

  /// What has been rated, e.g. "películas y música".
  String get ratedTopics => RatingCategory.values.where((c) => of(c).isNotEmpty).map((c) => c.noun).join(' y ');

  /// Short text for profile lists: the free text, or a summary of the ratings.
  String get preview {
    if (text.isNotEmpty) return text;
    if (ratings.isEmpty) return '';
    final count = ratings.length;
    return '$count ${count == 1 ? 'calificación' : 'calificaciones'} de $ratedTopics';
  }

  /// The bio as stored on the server, or null when it is empty.
  String? compose() {
    final cleanText = text.trim();
    final block = ratingsBlock;
    if (block.isEmpty) return cleanText.isEmpty ? null : cleanText;
    if (cleanText.isEmpty) return block;
    return '$cleanText\n\n$block';
  }

  bool get fits => (compose()?.length ?? 0) <= maxLength;

  RatedItem? find(RatedItem probe) => ratings.where((r) => r.sameAs(probe)).firstOrNull;

  ProfileBio withText(String newText) => ProfileBio(text: newText, ratings: ratings);

  /// Adds or updates a rating, placing it first in its category.
  ProfileBio withRating(RatedItem rating) => ProfileBio(
        text: text,
        ratings: [rating, ...ratings.where((r) => !r.sameAs(rating))],
      );

  ProfileBio without(RatedItem probe) => ProfileBio(
        text: text,
        ratings: ratings.where((r) => !r.sameAs(probe)).toList(),
      );
}
