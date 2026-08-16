import 'package:flutter/foundation.dart';

// ─── Notification Type Constants ───────────────────────────────────────────
class NotificationType {
  NotificationType._();

  static const String customerCreated = 'CUSTOMER_CREATED';
  static const String customerUpdated = 'CUSTOMER_UPDATED';
  static const String customerStageChanged = 'CUSTOMER_STAGE_CHANGED';

  static const String leadCreated = 'LEAD_CREATED';
  static const String leadUpdated = 'LEAD_UPDATED';
  static const String leadConverted = 'LEAD_CONVERTED';
  static const String leadFollowup = 'LEAD_FOLLOWUP';

  static const String taskAssigned = 'TASK_ASSIGNED';
  static const String taskUpdated = 'TASK_UPDATED';
  static const String taskCompleted = 'TASK_COMPLETED';
  static const String taskNotCompleted = 'TASK_NOT_COMPLETED';
  static const String taskReassigned = 'TASK_REASSIGNED';
  static const String taskAttachmentAdded = 'TASK_ATTACHMENT_ADDED';

  static const String installationUpdated = 'INSTALLATION_UPDATED';
  static const String installationCompleted = 'INSTALLATION_COMPLETED';

  static const String materialDispatched = 'MATERIAL_DISPATCHED';
  static const String materialReceived = 'MATERIAL_RECEIVED';

  static const String deliveryAssigned = 'DELIVERY_ASSIGNED';
  static const String deliveryStarted = 'DELIVERY_STARTED';
  static const String deliveryPhotoUploaded = 'DELIVERY_PHOTO_UPLOADED';
  static const String materialDelivered = 'MATERIAL_DELIVERED';

  static const String loanStatusChanged = 'LOAN_STATUS_CHANGED';
  static const String paymentAdded = 'PAYMENT_ADDED';
  static const String paymentUpdated = 'PAYMENT_UPDATED';
  static const String rtsUpdated = 'RTS_UPDATED';
  static const String subsidyUpdated = 'SUBSIDY_UPDATED';

  static const String importCompleted = 'IMPORT_COMPLETED';
  static const String importFailed = 'IMPORT_FAILED';

  static const String staffCreated = 'STAFF_CREATED';
  static const String staffUpdated = 'STAFF_UPDATED';

  static const String appUpdate = 'APP_UPDATE';
  static const String systemAnnouncement = 'SYSTEM_ANNOUNCEMENT';
  static const String testNotification = 'TEST_NOTIFICATION';
}

// ─── AppNotification Model ─────────────────────────────────────────────────
@immutable
class AppNotification {
  final String id;
  final String recipientUserId;
  final String notificationType;
  final String? entityTypeRaw;
  final String? entityIdRaw;
  final String title;
  final String message;
  final String? relatedRecordId;
  final String? taskId;
  final String? dispatchId;
  final Map<String, dynamic>? metadata;
  final String? eventId;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.recipientUserId,
    required this.notificationType,
    this.entityTypeRaw,
    this.entityIdRaw,
    required this.title,
    required this.message,
    this.relatedRecordId,
    this.taskId,
    this.dispatchId,
    this.metadata,
    this.eventId,
    required this.isRead,
    required this.createdAt,
  });

  String get notificationId => id;

  /// Effective entity type for deep link mapping
  String get entityType {
    if (entityTypeRaw != null && entityTypeRaw!.isNotEmpty) {
      return entityTypeRaw!.toLowerCase();
    }
    final type = notificationType.toUpperCase();
    if (type.contains('TASK')) return 'task';
    if (type.contains('CUSTOMER') ||
        type.contains('LOAN') ||
        type.contains('PAYMENT') ||
        type.contains('RTS') ||
        type.contains('SUBSIDY')) return 'customer';
    if (type.contains('LEAD')) return 'lead';
    if (type.contains('INSTALLATION')) return 'installation';
    if (type.contains('MATERIAL') && !type.contains('DELIVERY')) return 'material';
    if (type.contains('DELIVERY') || type.contains('DISPATCH')) return 'delivery';
    if (type.contains('STAFF')) return 'staff';
    if (type.contains('UPDATE')) return 'app_update';
    return 'system';
  }

  /// Effective target entity ID for opening the exact record
  String? get entityId => entityIdRaw ?? taskId ?? dispatchId ?? relatedRecordId;

  String? get navigationRecordId => entityId;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? json['notification_id']) as String,
      recipientUserId: (json['recipient_user_id'] ?? json['user_id']) as String,
      notificationType: (json['notification_type'] ?? 'SYSTEM') as String,
      entityTypeRaw: json['entity_type'] as String?,
      entityIdRaw: (json['entity_id'] ?? json['navigation_id']) as String?,
      title: (json['title'] ?? '') as String,
      message: (json['message'] ?? '') as String,
      relatedRecordId: json['related_record_id'] as String?,
      taskId: json['task_id'] as String?,
      dispatchId: json['dispatch_id'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      eventId: json['event_id'] as String?,
      isRead: (json['is_read'] as bool?) ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : DateTime.now(),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      recipientUserId: recipientUserId,
      notificationType: notificationType,
      entityTypeRaw: entityTypeRaw,
      entityIdRaw: entityIdRaw,
      title: title,
      message: message,
      relatedRecordId: relatedRecordId,
      taskId: taskId,
      dispatchId: dispatchId,
      metadata: metadata,
      eventId: eventId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
