import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'package:firebase_messaging/firebase_messaging.dart' as fb_msg;

import 'notification_repository.dart';
import 'notification_state.dart';

// Global flag to track Firebase initialization
bool _firebaseAvailable = false;

// ─── Background FCM Handler (must be top-level) ───────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(fb_msg.RemoteMessage message) async {
  debugPrint('[FCM Background] Message received: ${message.notification?.title}');
}

// ─── Notification Service ─────────────────────────────────────────────────
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  fb_msg.FirebaseMessaging? _fcm;
  String? _currentFcmToken;
  NotificationRepository? _repo;
  NotificationNotifier? _notifier;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'general_notifications',
    'General Notifications',
    description: 'Solar CRM app notifications',
    importance: Importance.high,
    playSound: true,
  );

  // ─── Initialize ──────────────────────────────────────────────────────────
  Future<void> initialize({
    required NotificationRepository repo,
    required NotificationNotifier notifier,
  }) async {
    _repo = repo;
    _notifier = notifier;

    await _initLocalNotifications();
    await _initFirebase();
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[LocalNotification] Tapped: payload=${response.payload}');
      },
    );

    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }

    debugPrint('[NotificationService] Local notifications initialized.');
  }

  Future<void> _initFirebase() async {
    try {
      await fb_core.Firebase.initializeApp();
      _firebaseAvailable = true;
      _fcm = fb_msg.FirebaseMessaging.instance;

      fb_msg.FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);

      fb_msg.FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      fb_msg.FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      debugPrint('[NotificationService] Firebase initialized successfully.');
    } catch (e) {
      _firebaseAvailable = false;
      debugPrint(
          '[NotificationService] Firebase init failed (google-services.json may be missing): $e');
      debugPrint('[NotificationService] App continues — realtime notifications still work.');
    }
  }

  // ─── Request Permission ───────────────────────────────────────────────────
  Future<bool> requestPermission() async {
    if (!_firebaseAvailable || _fcm == null) return false;
    try {
      final settings = await _fcm!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == fb_msg.AuthorizationStatus.authorized ||
          settings.authorizationStatus == fb_msg.AuthorizationStatus.provisional;
      debugPrint('[NotificationService] Permission: ${settings.authorizationStatus}');
      return granted;
    } catch (e) {
      debugPrint('[NotificationService] requestPermission error: $e');
      return false;
    }
  }

  // ─── Register Device Token ────────────────────────────────────────────────
  Future<void> registerDeviceToken(String userId) async {
    if (!_firebaseAvailable || _fcm == null || _repo == null) return;
    try {
      final token = await _fcm!.getToken();
      if (token == null) {
        debugPrint('[NotificationService] FCM token is null');
        return;
      }
      _currentFcmToken = token;
      await _repo!.registerDeviceToken(userId: userId, fcmToken: token);

      _fcm!.onTokenRefresh.listen((newToken) async {
        debugPrint('[NotificationService] FCM token refreshed');
        _currentFcmToken = newToken;
        await _repo!.registerDeviceToken(userId: userId, fcmToken: newToken);
      });
    } catch (e) {
      debugPrint('[NotificationService] registerDeviceToken error: $e');
    }
  }

  // ─── Remove Device Token on Logout ───────────────────────────────────────
  Future<void> removeDeviceToken(String userId) async {
    if (_repo == null || _currentFcmToken == null) return;
    try {
      await _repo!.removeDeviceToken(
          userId: userId, fcmToken: _currentFcmToken!);
      _currentFcmToken = null;
      debugPrint('[NotificationService] Device token removed on logout.');
    } catch (e) {
      debugPrint('[NotificationService] removeDeviceToken error: $e');
    }
  }

  // ─── Handle Foreground FCM Message ───────────────────────────────────────
  Future<void> _handleForegroundMessage(fb_msg.RemoteMessage message) async {
    debugPrint(
        '[NotificationService] Foreground FCM: ${message.notification?.title}');

    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && android != null) {
      await _showLocalNotification(
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: message.data['notification_type'],
      );
    }

    _notifier?.refresh();
  }

  // ─── Handle Notification Tap ──────────────────────────────────────────────
  void _handleNotificationTap(fb_msg.RemoteMessage message) {
    debugPrint('[NotificationService] Notification tapped (from background)');
    _notifier?.refresh();
  }

  // ─── Show Local Notification ──────────────────────────────────────────────
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
    );

    final details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  // ─── Show Test Local Notification ─────────────────────────────────────────
  Future<void> showTestLocalNotification() async {
    await _showLocalNotification(
      title: 'Test Notification',
      body: 'Notification service is working correctly.',
      payload: 'TEST_NOTIFICATION',
    );
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────
  void dispose() {
    _repo = null;
    _notifier = null;
    debugPrint('[NotificationService] Disposed.');
  }
}

// ─── Global Singleton Accessor ────────────────────────────────────────────
final notificationService = NotificationService();

// ─── Helper Extension ─────────────────────────────────────────────────────
extension NotificationSender on NotificationRepository {
  static NotificationRepository? _instance;

  static void setInstance(NotificationRepository repo) {
    _instance = repo;
  }

  static Future<void> send({
    required String recipientUserId,
    required String notificationType,
    required String title,
    required String message,
    String? relatedRecordId,
    String? taskId,
    String? dispatchId,
    Map<String, dynamic>? metadata,
    String? eventId,
  }) async {
    if (_instance == null) {
      debugPrint('[NotificationSender] Repository not initialized, skipping notification.');
      return;
    }
    await _instance!.sendNotification(
      recipientUserId: recipientUserId,
      notificationType: notificationType,
      title: title,
      message: message,
      relatedRecordId: relatedRecordId,
      taskId: taskId,
      dispatchId: dispatchId,
      metadata: metadata,
      eventId: eventId,
    );
  }
}
