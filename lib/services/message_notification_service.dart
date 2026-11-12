import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart';
import '../models/chat_item.dart';
import '../models/user_profile.dart';
import '../screens/chat_conversation_screen.dart';
import 'auth_service.dart';
import 'chat_crypto.dart';
import 'chat_unread_service.dart';

class MessageNotificationService {
  static final MessageNotificationService _instance = MessageNotificationService._internal();
  factory MessageNotificationService() => _instance;
  MessageNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _checkTimer;
  String? activeConversationId;
  final Map<String, DateTime> _lastKnownMessageTime = {};
  final Map<String, ChatItem> _knownChats = {};
  bool _isFirstCheck = true;
  bool _isChecking = false;

  /// Initializes the local notification plugin across all operating systems:
  /// Android, iOS, macOS, Linux, Windows, and Web.
  Future<void> init() async {
    if (_initialized) return;

    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialized = true;
      _startPeriodicChecking();
      return;
    }

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Abrir',
      );
      const windowsSettings = WindowsInitializationSettings(
        appName: 'Brote',
        appUserModelId: 'com.example.brote',
        guid: 'f0c43666-fa3d-4c3e-8f5f-141684346808',
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      );

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _initialized = true;
      _requestPermissions();
      _startPeriodicChecking();
    } catch (e) {
      debugPrint('Error initializing MessageNotificationService: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
    }
  }

  void _startPeriodicChecking() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkForNewMessages();
    });
    AuthService().chatsRefreshNotifier.addListener(checkForNewMessages);
  }

  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _lastKnownMessageTime.clear();
    _knownChats.clear();
    _isFirstCheck = true;
  }

  /// Checks conversations on the server and displays OS notification for incoming messages
  Future<void> checkForNewMessages() async {
    if (!AuthService().isAuthenticated || _isChecking) return;
    _isChecking = true;

    try {
      final chats = await AuthService().getConversations();
      ChatUnreadService().update(chats);

      if (_isFirstCheck) {
        // Record initial state so historical unread messages don't spam notifications on launch
        for (final chat in chats) {
          _knownChats[chat.id] = chat;
          if (chat.lastMessageAt != null) {
            _lastKnownMessageTime[chat.id] = chat.lastMessageAt!;
          }
        }
        _isFirstCheck = false;
        return;
      }

      for (final chat in chats) {
        _knownChats[chat.id] = chat;
        final lastTime = chat.lastMessageAt;
        if (lastTime == null) continue;

        final knownTime = _lastKnownMessageTime[chat.id];
        final isNew = knownTime == null || lastTime.isAfter(knownTime);

        // Check if there are unread messages and user is not inside this specific conversation
        if (chat.unreadCount > 0 && chat.id != activeConversationId && isNew) {
          String bodyText = chat.lastMessage;

          // Attempt decryption if encrypted
          if (ChatCipher.isEncrypted(chat.lastMessage)) {
            final otherId = chat.otherParticipant?.id;
            if (otherId != null) {
              final key = await ChatCrypto().keyForConversation(chat.id, otherId);
              if (key != null) {
                final decrypted = await ChatCipher.decryptPayload(chat.lastMessage, key);
                if (decrypted != null) {
                  bodyText = decrypted.preview;
                }
              }
            }
            if (ChatCipher.isEncrypted(bodyText)) {
              bodyText = '🔒 Mensaje nuevo';
            }
          }

          await showNotification(
            id: chat.id.hashCode,
            title: chat.displayName,
            body: bodyText.isNotEmpty ? bodyText : 'Nuevo mensaje',
            payload: chat.id,
          );
        }

        _lastKnownMessageTime[chat.id] = lastTime;
      }
    } catch (e) {
      debugPrint('Error checking for new messages: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// Displays an operating system notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'brote_chat_messages',
        'Mensajes de Chat',
        channelDescription: 'Notificaciones para mensajes entrantes en Brote',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const linuxDetails = LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.normal,
      );

      const windowsDetails = WindowsNotificationDetails();

      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
        linux: linuxDetails,
        windows: windowsDetails,
      );

      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Failed to display OS notification: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final conversationId = response.payload;
    if (conversationId == null || conversationId.isEmpty) return;

    final chat = _knownChats[conversationId];
    final other = chat?.otherParticipant ??
        UserProfile(
          id: conversationId,
          username: chat?.username ?? 'usuario',
          displayName: chat?.displayName ?? 'Usuario',
        );

    final nav = BroteApp.navigatorKey.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatConversationScreen(
            conversationId: conversationId,
            otherParticipant: other,
          ),
        ),
      );
    }
  }
}
