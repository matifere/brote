import 'post_content.dart';
import 'user_profile.dart';

enum NotificationKind { like, follow, followRequest, followAccepted, message, unknown }

/// Something that happened to the user: a like, a new follower, a message...
class AppNotification {
  final String id;
  final NotificationKind kind;
  final UserProfile actor;
  final String? postId;
  final String? postContent;
  final String? conversationId;
  final DateTime? createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.kind,
    required this.actor,
    this.postId,
    this.postContent,
    this.conversationId,
    this.createdAt,
    this.isRead = false,
  });

  static NotificationKind _kindOf(String? type) => switch (type) {
        'like' => NotificationKind.like,
        'follow' => NotificationKind.follow,
        'follow_request' => NotificationKind.followRequest,
        'follow_accepted' => NotificationKind.followAccepted,
        'message' => NotificationKind.message,
        _ => NotificationKind.unknown,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawActor = json['actor'];
    final actor = rawActor is Map ? Map<String, dynamic>.from(rawActor) : const <String, dynamic>{};
    return AppNotification(
      id: json['id'].toString(),
      kind: _kindOf(json['type'] as String?),
      actor: UserProfile(
        id: actor['id']?.toString() ?? '',
        username: actor['username'] as String? ?? 'usuario',
        displayName: actor['displayName'] as String? ?? actor['username'] as String? ?? 'Usuario',
        avatarUrl: actor['avatarUrl'] as String?,
      ),
      postId: json['postId'] as String?,
      postContent: json['postContent'] as String?,
      conversationId: json['conversationId'] as String?,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  /// What happened, after the actor's name.
  String get message => switch (kind) {
        NotificationKind.like => 'le dio me gusta a tu publicación',
        NotificationKind.follow => 'empezó a seguirte',
        NotificationKind.followRequest => 'quiere seguirte',
        NotificationKind.followAccepted => 'aceptó tu solicitud de seguimiento',
        NotificationKind.message => 'te envió un mensaje',
        NotificationKind.unknown => 'tiene novedades para vos',
      };

  /// A short line about the liked post: the reviewed title, or the start of its text.
  String? get postPreview {
    final content = postContent;
    if (content == null || content.trim().isEmpty) return null;
    final parsed = PostContent.parse(content);
    if (parsed.review != null) return 'Reseña de ${parsed.review!.title}';
    final firstLine = parsed.body.split('\n').first.trim();
    if (firstLine.isEmpty) return null;
    return firstLine.length > 80 ? '${firstLine.substring(0, 79).trimRight()}…' : firstLine;
  }

  String get timeAgo {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inDays > 7) return '${createdAt!.day}/${createdAt!.month}/${createdAt!.year}';
    if (diff.inDays >= 1) return 'hace ${diff.inDays} d';
    if (diff.inHours >= 1) return 'hace ${diff.inHours} h';
    if (diff.inMinutes >= 1) return 'hace ${diff.inMinutes} m';
    return 'recién';
  }
}
