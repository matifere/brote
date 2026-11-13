class ChatMessageReply {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final String? mediaUrl;

  const ChatMessageReply({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.mediaUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderName': senderName,
    'text': text,
    if (mediaUrl != null && mediaUrl!.isNotEmpty) 'mediaUrl': mediaUrl,
  };

  factory ChatMessageReply.fromJson(Map<String, dynamic> json) => ChatMessageReply(
    id: json['id']?.toString() ?? '',
    senderId: json['senderId']?.toString() ?? json['sender_id']?.toString() ?? '',
    senderName: json['senderName'] as String? ?? json['sender_name'] as String? ?? 'Usuario',
    text: json['text'] as String? ?? '',
    mediaUrl: json['mediaUrl'] as String? ?? json['media_url'] as String?,
  );
}

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
  final ChatMessageReply? reply;

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
    this.reply,
  });

  String get timeFormatted {
    if (createdAt == null) return '';
    return '${createdAt!.hour}:${createdAt!.minute.toString().padLeft(2, '0')}';
  }

  bool get isGif =>
      mediaUrl != null &&
      (mediaUrl!.toLowerCase().contains('.gif') || mediaUrl!.contains('giphy.com'));

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    final rawDate = json['createdAt'] ?? json['created_at'];
    if (rawDate != null) {
      dt = DateTime.tryParse(rawDate.toString())?.toLocal();
    }

    ChatMessageReply? reply;
    if (json['reply'] is Map<String, dynamic>) {
      reply = ChatMessageReply.fromJson(json['reply'] as Map<String, dynamic>);
    } else if (json['reply_to'] is Map<String, dynamic>) {
      reply = ChatMessageReply.fromJson(json['reply_to'] as Map<String, dynamic>);
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
      reply: reply,
    );
  }
}
