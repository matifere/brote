import 'user_profile.dart';

class PostComment {
  final String id;
  final String postId;
  final String? parentId;
  final String? replyToUsername;
  final UserProfile author;
  final String content;
  final DateTime? createdAt;
  int likesCount;
  bool isLiked;

  PostComment({
    required this.id,
    required this.postId,
    this.parentId,
    this.replyToUsername,
    required this.author,
    required this.content,
    this.createdAt,
    this.likesCount = 0,
    this.isLiked = false,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) {
    final rawAuthor = json['author'];
    final author = rawAuthor is Map ? Map<String, dynamic>.from(rawAuthor) : const <String, dynamic>{};
    return PostComment(
      id: json['id'].toString(),
      postId: json['postId']?.toString() ?? '',
      parentId: json['parentId']?.toString(),
      replyToUsername: json['replyToUsername'] as String?,
      author: UserProfile(
        id: author['id']?.toString() ?? '',
        username: author['username'] as String? ?? 'usuario',
        displayName: author['displayName'] as String? ?? author['username'] as String? ?? 'Usuario',
        avatarUrl: author['avatarUrl'] as String?,
      ),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      isLiked: json['isLiked'] == true,
    );
  }

  String get timeAgo {
    if (createdAt == null) return 'recién';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inDays > 7) return '${createdAt!.day}/${createdAt!.month}/${createdAt!.year}';
    if (diff.inDays >= 1) return 'hace ${diff.inDays} d';
    if (diff.inHours >= 1) return 'hace ${diff.inHours} h';
    if (diff.inMinutes >= 1) return 'hace ${diff.inMinutes} m';
    return 'recién';
  }
}
