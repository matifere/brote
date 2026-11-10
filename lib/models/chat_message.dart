class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String senderUsername;
  final String? senderAvatarUrl;
  final String content;
  final String? mediaUrl;
  final DateTime? createdAt;
  final bool isMe;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderUsername,
    this.senderAvatarUrl,
    required this.content,
    this.mediaUrl,
    this.createdAt,
    required this.isMe,
  });

  String get timeFormatted {
    if (createdAt == null) return '';
    return '${createdAt!.hour}:${createdAt!.minute.toString().padLeft(2, '0')}';
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    final rawDate = json['createdAt'] ?? json['created_at'];
    if (rawDate != null) {
      dt = DateTime.tryParse(rawDate.toString())?.toLocal();
    }

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? json['conversation_id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? json['sender_id']?.toString() ?? '',
      senderName: json['senderName'] as String? ?? json['sender_name'] as String? ?? 'Usuario',
      senderUsername: json['senderUsername'] as String? ?? json['sender_username'] as String? ?? 'usuario',
      senderAvatarUrl: json['senderAvatarUrl'] as String? ?? json['sender_avatar_url'] as String?,
      content: json['content'] as String? ?? '',
      mediaUrl: json['mediaUrl'] as String? ?? json['media_url'] as String?,
      createdAt: dt,
      isMe: json['isMe'] as bool? ?? json['is_me'] as bool? ?? false,
    );
  }
}
