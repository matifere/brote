import 'user_profile.dart';

class ChatItem {
  final String id;
  final bool isGroup;
  final String? title;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isRead;
  final UserProfile? otherParticipant;

  ChatItem({
    required this.id,
    this.isGroup = false,
    this.title,
    required this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isRead = true,
    this.otherParticipant,
  });

  String get displayName {
    if (isGroup && title != null && title!.isNotEmpty) {
      return title!;
    }
    return otherParticipant?.displayName ?? 'Usuario';
  }

  String get username {
    return otherParticipant?.username ?? 'usuario';
  }

  String? get avatarUrl {
    return otherParticipant?.avatarUrl;
  }

  bool get isVerified {
    return otherParticipant?.isVerified ?? false;
  }

  bool get isPrivate {
    return otherParticipant?.isPrivate ?? false;
  }

  String get timeFormatted {
    if (lastMessageAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(lastMessageAt!);

    if (diff.inDays >= 7) {
      return '${lastMessageAt!.day}/${lastMessageAt!.month}';
    } else if (diff.inDays >= 1) {
      return 'hace ${diff.inDays} d';
    } else if (diff.inHours >= 1) {
      return '${lastMessageAt!.hour}:${lastMessageAt!.minute.toString().padLeft(2, '0')}';
    } else if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} m';
    } else {
      return 'ahora';
    }
  }

  factory ChatItem.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    final rawDate = json['lastMessageTime'] ?? json['last_message_at'] ?? json['lastMessageAt'];
    if (rawDate != null) {
      dt = DateTime.tryParse(rawDate.toString())?.toLocal();
    }

    UserProfile? other;
    if (json['otherParticipant'] != null && json['otherParticipant'] is Map) {
      other = UserProfile.fromJson(json['otherParticipant'] as Map<String, dynamic>);
    }

    return ChatItem(
      id: json['id'].toString(),
      isGroup: json['isGroup'] as bool? ?? json['is_group'] as bool? ?? false,
      title: json['title'] as String?,
      lastMessage: json['lastMessage'] as String? ?? json['last_message'] as String? ?? '',
      lastMessageAt: dt,
      unreadCount: (json['unreadCount'] as num? ?? json['unread_count'] as num? ?? 0).toInt(),
      isRead: json['isRead'] as bool? ?? json['is_read'] as bool? ?? true,
      otherParticipant: other,
    );
  }
}

class ChatCandidate {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isPrivate;
  final bool isFollowing;
  final bool isFollower;
  final bool isPending;
  final bool canMessage;

  ChatCandidate({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.isPrivate = false,
    this.isFollowing = false,
    this.isFollower = false,
    this.isPending = false,
    required this.canMessage,
  });

  factory ChatCandidate.fromJson(Map<String, dynamic> json) {
    return ChatCandidate(
      id: json['id'].toString(),
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['display_name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? json['avatar_url'] as String?,
      isVerified: json['isVerified'] as bool? ?? json['is_verified'] as bool? ?? false,
      isPrivate: json['isPrivate'] as bool? ?? json['is_private'] as bool? ?? false,
      isFollowing: json['isFollowing'] as bool? ?? json['is_following'] as bool? ?? false,
      isFollower: json['isFollower'] as bool? ?? json['is_follower'] as bool? ?? false,
      isPending: json['isPending'] as bool? ?? json['is_pending'] as bool? ?? false,
      canMessage: json['canMessage'] as bool? ?? json['can_message'] as bool? ?? true,
    );
  }
}
