import 'package:flutter/foundation.dart';
import '../models/chat_item.dart';

/// How many conversations have unread messages, for the Chats tab badge.
///
/// ChatsScreen lives in the navigation IndexedStack and already reloads the
/// inbox every few seconds, so it reports each load here instead of the badge
/// polling the server on its own.
class ChatUnreadService {
  static final ChatUnreadService _instance = ChatUnreadService._internal();
  factory ChatUnreadService() => _instance;
  ChatUnreadService._internal();

  final ValueNotifier<int> unreadChats = ValueNotifier(0);

  void update(List<ChatItem> chats) {
    unreadChats.value = chats.where((c) => c.unreadCount > 0).length;
  }

  void clear() => unreadChats.value = 0;
}
