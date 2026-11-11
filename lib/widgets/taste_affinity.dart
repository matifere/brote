import 'package:flutter/material.dart';
import '../models/rating.dart';
import 'rating_stars.dart';

/// The same movie, song or album rated by both users.
class TasteMatch {
  final RatedItem mine;
  final RatedItem theirs;

  const TasteMatch({required this.mine, required this.theirs});

  /// 1 when both gave the same stars, 0 when one gave 1 and the other 5.
  double get agreement => 1 - (mine.stars - theirs.stars).abs() / 4;
}

/// What two profiles have in common, compared from the ratings in their bios.
class TasteAffinity {
  final List<TasteMatch> matches;

  const TasteAffinity(this.matches);

  /// Null when they have nothing rated in common.
  static TasteAffinity? compare(ProfileBio mine, ProfileBio theirs) {
    final matches = <TasteMatch>[];
    for (final category in RatingCategory.values) {
      final myRatings = mine.of(category);
      for (final theirRating in theirs.of(category)) {
        final myRating = myRatings.where((r) => r.sameAs(theirRating)).firstOrNull;
        if (myRating != null) matches.add(TasteMatch(mine: myRating, theirs: theirRating));
      }
    }
    return matches.isEmpty ? null : TasteAffinity(matches);
  }

  int count(RatingCategory category) => matches.where((m) => m.mine.category == category).length;

  /// Average agreement on the stars, from 0 to 100.
  int get agreementPercent =>
      (matches.map((m) => m.agreement).reduce((a, b) => a + b) / matches.length * 100).round();

  /// E.g. "Coinciden en 2 películas y 1 tema o álbum".
  String get summary {
    final movies = count(RatingCategory.movie);
    final music = count(RatingCategory.music);
    final parts = [
      if (movies > 0) movies == 1 ? '1 película' : '$movies películas',
      if (music > 0) music == 1 ? '1 tema o álbum' : '$music temas o álbumes',
    ];
    return 'Coinciden en ${parts.join(' y ')}';
  }
}

/// Card on someone else's profile with the ratings you have in common.
class TasteAffinityCard extends StatelessWidget {
  static const int _maxShown = 6;

  final TasteAffinity affinity;
  final String otherUsername;

  const TasteAffinityCard({super.key, required this.affinity, required this.otherUsername});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shown = affinity.matches.take(_maxShown).toList();
    final hidden = affinity.matches.length - shown.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.join_inner_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Gustos en común',
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Tooltip(
                message: 'Qué tan parecidas son sus estrellas en lo que calificaron los dos',
                child: Text(
                  '${affinity.agreementPercent}% de acuerdo',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            affinity.summary,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (final match in shown) _buildMatchRow(match, colorScheme, textTheme),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hidden == 1 ? 'y 1 más' : 'y $hidden más',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMatchRow(TasteMatch match, ColorScheme colorScheme, TextTheme textTheme) {
    final item = match.theirs;
    final detail = item.detail;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            item.category == RatingCategory.movie ? Icons.local_movies_outlined : Icons.music_note_rounded,
            size: 15,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (detail != null)
                    TextSpan(
                      text: item.category == RatingCategory.movie ? ' ($detail)' : ' · $detail',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          _buildStars('Vos', match.mine.stars, colorScheme, textTheme),
          const SizedBox(width: 10),
          _buildStars('@$otherUsername', match.theirs.stars, colorScheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildStars(String who, int stars, ColorScheme colorScheme, TextTheme textTheme) {
    return Tooltip(
      message: '$who: $stars ${stars == 1 ? 'estrella' : 'estrellas'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 64),
            child: Text(
              who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 10),
            ),
          ),
          RatingStars(stars: stars, size: 11),
        ],
      ),
    );
  }
}
