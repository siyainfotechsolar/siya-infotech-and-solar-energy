import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_model.dart';

class NotificationRepository {
  final SupabaseClient _supabase;
  static const int _pageSize = 20;

  NotificationRepository(this._supabase);

  // ─── Fetch paginated notifications ───────────────────────────────────────
  Future<List<AppNotification>> getNotifications({
    int page = 0,
    bool unreadOnly = false,
  }) async {
    try {
      var query = _supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .range(page * _pageSize, (page + 1) * _pageSize - 1);

      if (unreadOnly) {
        query = _supabase
            .from('notifications')
            .select()
            .eq('is_read', false)
            .order('created_at', ascending: false)
            .range(page * _pageSize, (page + 1) * _pageSize - 1);
      }

      final response = await query;
      return (response as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[NotificationRepo] getNotifications error: $e');
      return [];
    }
  }

  // ─── Get unread count ─────────────────────────────────────────────────────
  Future<int> getUnreadCount() async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('is_read', false);
      return (response as List).length;
    } catch (e) {
      debugPrint('[NotificationRepo] getUnreadCount error: $e');
      return 0;
    }
  }

  // ─── Mark single notification as read ────────────────────────────────────
  Future<void> markAsRead(String id) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (e) {
      debugPrint('[NotificationRepo] markAsRead error: $e');
    }
  }

  // ─── Mark all as read ─────────────────────────────────────────────────────
  Future<void> markAllAsRead(String userId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('[NotificationRepo] markAllAsRead error: $e');
    }
  }

  // ─── Register device token ────────────────────────────────────────────────
  Future<void> registerDeviceToken({
    required String userId,
    required String fcmToken,
    String? deviceId,
    String platform = 'android',
  }) async {
    try {
      // Upsert: if same user+token exists, update last_seen_at; else insert
      await _supabase.from('user_devices').upsert(
        {
          'user_id': userId,
          'fcm_token': fcmToken,
          'platform': platform,
          'device_id': deviceId,
          'is_active': true,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,fcm_token',
      );
      debugPrint('[NotificationRepo] Device token registered.');
    } catch (e) {
      debugPrint('[NotificationRepo] registerDeviceToken error: $e');
    }
  }

  // ─── Deactivate device token on logout ───────────────────────────────────
  Future<void> removeDeviceToken({
    required String userId,
    required String fcmToken,
  }) async {
    try {
      await _supabase
          .from('user_devices')
          .update({'is_active': false, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId)
          .eq('fcm_token', fcmToken);
      debugPrint('[NotificationRepo] Device token deactivated.');
    } catch (e) {
      debugPrint('[NotificationRepo] removeDeviceToken error: $e');
    }
  }

  // ─── Call Edge Function to create notification ────────────────────────────
  Future<void> sendNotification({
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
    try {
      final effectiveEntityId = taskId ?? dispatchId ?? relatedRecordId;
      String entityType;
      final typeUpper = notificationType.toUpperCase();
      if (typeUpper.contains('TASK')) {
        entityType = 'task';
      } else if (typeUpper.contains('CUSTOMER') ||
          typeUpper.contains('PAYMENT') ||
          typeUpper.contains('LOAN') ||
          typeUpper.contains('RTS') ||
          typeUpper.contains('SUBSIDY')) {
        entityType = 'customer';
      } else if (typeUpper.contains('LEAD')) {
        entityType = 'lead';
      } else if (typeUpper.contains('INSTALLATION')) {
        entityType = 'installation';
      } else if (typeUpper.contains('MATERIAL') && !typeUpper.contains('DELIVERY')) {
        entityType = 'material';
      } else if (typeUpper.contains('DELIVERY') || typeUpper.contains('DISPATCH')) {
        entityType = 'delivery';
      } else if (typeUpper.contains('STAFF')) {
        entityType = 'staff';
      } else if (typeUpper.contains('UPDATE')) {
        entityType = 'app_update';
      } else {
        entityType = 'system';
      }

      final uniqueEventId = eventId ??
          '${notificationType}_${effectiveEntityId ?? DateTime.now().millisecondsSinceEpoch}_$recipientUserId';

      try {
        await _supabase.from('notifications').insert({
          'recipient_user_id': recipientUserId,
          'user_id': recipientUserId,
          'notification_type': notificationType,
          'entity_type': entityType,
          'entity_id': effectiveEntityId,
          'title': title,
          'message': message,
          'related_record_id': relatedRecordId,
          'task_id': taskId,
          'dispatch_id': dispatchId,
          'metadata': metadata,
          'event_id': uniqueEventId,
          'is_read': false,
        });
      } catch (dbErr) {
        // Fallback to Edge function if direct DB insert fails
        await _supabase.functions.invoke(
          'send-notification',
          body: {
            'recipient_user_id': recipientUserId,
            'notification_type': notificationType,
            'entity_type': entityType,
            'entity_id': effectiveEntityId,
            'title': title,
            'message': message,
            if (relatedRecordId != null) 'related_record_id': relatedRecordId,
            if (taskId != null) 'task_id': taskId,
            if (dispatchId != null) 'dispatch_id': dispatchId,
            if (metadata != null) 'metadata': metadata,
            'event_id': uniqueEventId,
          },
        );
      }
      debugPrint('[NotificationRepo] Notification sent: $notificationType → $recipientUserId');
    } catch (e) {
      // Notification failure must NOT break core app functionality
      debugPrint('[NotificationRepo] sendNotification error (non-fatal): $e');
    }
  }

  // ─── Notify all Active Admins ──────────────────────────────────────────────
  Future<void> notifyAdmins({
    required String notificationType,
    required String title,
    required String message,
    String? relatedRecordId,
    String? taskId,
    String? dispatchId,
    Map<String, dynamic>? metadata,
    String? eventId,
  }) async {
    try {
      final admins = await _supabase
          .from('staff')
          .select('id')
          .eq('role', 'admin')
          .eq('status', 'active');
      
      final adminIds = (admins as List).map((a) => a['id'] as String).toList();
      for (final adminId in adminIds) {
        final uniqueEventId = eventId != null 
            ? '${eventId}_$adminId' 
            : '${notificationType}_${relatedRecordId ?? taskId ?? dispatchId ?? DateTime.now().millisecondsSinceEpoch}_$adminId';
            
        await sendNotification(
          recipientUserId: adminId,
          notificationType: notificationType,
          title: title,
          message: message,
          relatedRecordId: relatedRecordId,
          taskId: taskId,
          dispatchId: dispatchId,
          metadata: metadata,
          eventId: uniqueEventId,
        );
      }
    } catch (e) {
      debugPrint('[NotificationRepo] notifyAdmins error: $e');
    }
  }
}
