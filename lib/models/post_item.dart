import 'post_content.dart';

class PostItem {
  final String id;
  final String authorId;
  final String authorName;
  final String authorUsername;
  final String? authorAvatarUrl;
  final bool isVerified;
  final String content;
  final String? imageUrl;
  final List<String> imageUrls;
  final DateTime? createdAt;
  int likesCount;
  int commentsCount;
  int repostsCount;
  bool isLiked;
  bool isBookmarked;
  final bool isFollowingAuthor;
  final bool isSensitive;
  final bool isHidden;
  final int reportsCount;

  PostItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorUsername,
    this.authorAvatarUrl,
    this.isVerified = false,
    required this.content,
    this.imageUrl,
    this.imageUrls = const [],
    this.createdAt,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.repostsCount = 0,
    this.isLiked = false,
    this.isBookmarked = false,
    this.isFollowingAuthor = false,
    this.isSensitive = false,
    this.isHidden = false,
    this.reportsCount = 0,
  });

  /// Review header, body and 24-hour mark encoded in the post text.
  late final PostContent parsedContent = PostContent.parse(content);

  DateTime? get expiresAt => parsedContent.isEphemeral && createdAt != null
      ? createdAt!.add(PostContent.ephemeralDuration)
      : null;

  bool get isExpired => expiresAt != null && !DateTime.now().isBefore(expiresAt!);

  /// Time left for 24-hour posts, e.g. "quedan 5 h".
  String? get timeLeft {
    if (expiresAt == null) return null;
    final left = expiresAt!.difference(DateTime.now());
    if (left.inHours >= 1) return 'quedan ${left.inHours} h';
    if (left.inMinutes >= 1) return 'quedan ${left.inMinutes} min';
    return 'por vencer';
  }

  String get timeAgo {
    if (createdAt == null) return 'recién';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inDays > 7) {
      return '${createdAt!.day}/${createdAt!.month}/${createdAt!.year}';
    } else if (diff.inDays >= 1) {
      return 'hace ${diff.inDays} d';
    } else if (diff.inHours >= 1) {
      return 'hace ${diff.inHours} h';
    } else if (diff.inMinutes >= 1) {
      return 'hace ${diff.inMinutes} m';
    } else {
      return 'recién';
    }
  }

  factory PostItem.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    final dateRaw = json['createdAt'] ?? json['created_at'];
    if (dateRaw != null) {
      dt = DateTime.tryParse(dateRaw.toString())?.toLocal();
    }
    final rawUrls = json['imageUrls'] ?? json['image_urls'] ?? json['media_urls'];
    final parsedUrls = (rawUrls is List)
        ? rawUrls.map((e) => e.toString()).where((u) => u.isNotEmpty).toList()
        : <String>[];
    final singleUrl = json['imageUrl'] as String? ?? json['image_url'] as String?;
    final allUrls = parsedUrls.isNotEmpty
        ? parsedUrls
        : (singleUrl != null && singleUrl.isNotEmpty ? [singleUrl] : const <String>[]);

    return PostItem(
      id: json['id'].toString(),
      authorId: json['authorId']?.toString() ?? json['author_id']?.toString() ?? '',
      authorName: json['authorName'] as String? ?? json['author_name'] as String? ?? 'Usuario',
      authorUsername: json['authorUsername'] as String? ?? json['author_username'] as String? ?? 'usuario',
      authorAvatarUrl: json['authorAvatarUrl'] as String? ?? json['author_avatar_url'] as String?,
      isVerified: json['isVerified'] as bool? ?? json['is_verified'] as bool? ?? false,
      content: json['content'] as String? ?? json['text'] as String? ?? '',
      imageUrl: singleUrl ?? (allUrls.isNotEmpty ? allUrls.first : null),
      imageUrls: allUrls,
      createdAt: dt,
      likesCount: (json['likesCount'] as num? ?? json['likes_count'] as num? ?? 0).toInt(),
      commentsCount: (json['commentsCount'] as num? ?? json['comments_count'] as num? ?? 0).toInt(),
      repostsCount: (json['repostsCount'] as num? ?? json['reposts_count'] as num? ?? 0).toInt(),
      isLiked: json['isLiked'] as bool? ?? json['is_liked'] as bool? ?? false,
      isBookmarked: json['isBookmarked'] as bool? ?? json['is_bookmarked'] as bool? ?? false,
      isFollowingAuthor: json['isFollowingAuthor'] as bool? ?? json['is_following_author'] as bool? ?? false,
      isSensitive: json['isSensitive'] as bool? ?? json['is_sensitive'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? json['is_hidden'] as bool? ?? false,
      reportsCount: (json['reportsCount'] as num? ?? json['reports_count'] as num? ?? 0).toInt(),
    );
  }
}
