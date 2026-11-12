import 'user_profile.dart';

class ReportedPostPreview {
  final String id;
  final String content;
  final String? imageUrl;
  final bool isSensitive;
  final bool isHidden;
  final int reportsCount;
  final String? authorId;
  final String authorUsername;
  final String authorName;

  const ReportedPostPreview({
    required this.id,
    required this.content,
    this.imageUrl,
    this.isSensitive = false,
    this.isHidden = false,
    this.reportsCount = 0,
    this.authorId,
    required this.authorUsername,
    required this.authorName,
  });

  factory ReportedPostPreview.fromJson(Map<String, dynamic> json) {
    return ReportedPostPreview(
      id: json['id']?.toString() ?? '',
      content: json['content'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      isSensitive: json['isSensitive'] == true,
      isHidden: json['isHidden'] == true,
      reportsCount: (json['reportsCount'] as num?)?.toInt() ?? 0,
      authorId: json['authorId']?.toString(),
      authorUsername: json['authorUsername'] as String? ?? 'usuario',
      authorName: json['authorName'] as String? ?? 'Usuario',
    );
  }
}

class ReportedCommentPreview {
  final String id;
  final String content;
  final bool isHidden;
  final int reportsCount;
  final String? authorId;
  final String authorUsername;
  final String authorName;

  const ReportedCommentPreview({
    required this.id,
    required this.content,
    this.isHidden = false,
    this.reportsCount = 0,
    this.authorId,
    required this.authorUsername,
    required this.authorName,
  });

  factory ReportedCommentPreview.fromJson(Map<String, dynamic> json) {
    return ReportedCommentPreview(
      id: json['id']?.toString() ?? '',
      content: json['content'] as String? ?? '',
      isHidden: json['isHidden'] == true,
      reportsCount: (json['reportsCount'] as num?)?.toInt() ?? 0,
      authorId: json['authorId']?.toString(),
      authorUsername: json['authorUsername'] as String? ?? 'usuario',
      authorName: json['authorName'] as String? ?? 'Usuario',
    );
  }
}

class ReportItem {
  final String id;
  final String reason;
  final String? details;
  final String status; // 'pending', 'resolved', 'dismissed'
  final String? actionTaken;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final UserProfile? reporter;
  final ReportedPostPreview? post;
  final ReportedCommentPreview? comment;
  final UserProfile? user;

  const ReportItem({
    required this.id,
    required this.reason,
    this.details,
    required this.status,
    this.actionTaken,
    this.createdAt,
    this.resolvedAt,
    this.reporter,
    this.post,
    this.comment,
    this.user,
  });

  String get reasonLabel {
    switch (reason.toLowerCase()) {
      case 'spam':
        return 'Spam o estafa';
      case 'explicit':
        return 'Contenido explícito';
      case 'harassment':
        return 'Acoso u odio';
      case 'violence':
        return 'Violencia';
      case 'other':
      default:
        return 'Otro motivo';
    }
  }

  factory ReportItem.fromJson(Map<String, dynamic> json) {
    final repJson = json['reporter'];
    final postJson = json['post'];
    final commentJson = json['comment'];
    final userJson = json['user'];

    return ReportItem(
      id: json['id']?.toString() ?? '',
      reason: json['reason'] as String? ?? 'other',
      details: json['details'] as String?,
      status: json['status'] as String? ?? 'pending',
      actionTaken: json['actionTaken'] as String?,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      resolvedAt: DateTime.tryParse(json['resolvedAt']?.toString() ?? '')?.toLocal(),
      reporter: repJson is Map ? UserProfile.fromJson(Map<String, dynamic>.from(repJson)) : null,
      post: postJson is Map ? ReportedPostPreview.fromJson(Map<String, dynamic>.from(postJson)) : null,
      comment: commentJson is Map ? ReportedCommentPreview.fromJson(Map<String, dynamic>.from(commentJson)) : null,
      user: userJson is Map ? UserProfile.fromJson(Map<String, dynamic>.from(userJson)) : null,
    );
  }
}
