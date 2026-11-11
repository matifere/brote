import 'rating.dart';

/// A post's text split into its optional review header, body and 24-hour mark.
///
/// The posts API only stores text, so both extras are encoded in it: a first
/// line like `🎬 Dune (2021) ★★★★☆` makes the post a review, and a last line
/// `⏳ 24 h` makes it disappear from the app 24 hours after it was created.
class PostContent {
  static const String ephemeralTag = '⏳ 24 h';
  static const Duration ephemeralDuration = Duration(hours: 24);

  final String body;
  final RatedItem? review;
  final bool isEphemeral;

  const PostContent({this.body = '', this.review, this.isEphemeral = false});

  factory PostContent.parse(String content) {
    var lines = content.trim().split('\n');

    final isEphemeral = lines.last.trim() == ephemeralTag;
    if (isEphemeral) lines = lines.sublist(0, lines.length - 1);

    RatedItem? review;
    if (lines.isNotEmpty) {
      review = RatedItem.decodeLine(lines.first);
      if (review != null) lines = lines.sublist(1);
    }

    return PostContent(body: lines.join('\n').trim(), review: review, isEphemeral: isEphemeral);
  }

  String compose() => [
        if (review != null) review!.encodeLine(),
        if (body.trim().isNotEmpty) body.trim(),
        if (isEphemeral) ephemeralTag,
      ].join('\n\n');
}
