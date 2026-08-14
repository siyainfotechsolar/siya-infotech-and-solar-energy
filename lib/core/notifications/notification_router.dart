import 'package:flutter/material.dart';
import 'notification_model.dart';

/// Routes a tapped notification to the correct screen.
/// Handles missing records gracefully without crashing.
class NotificationRouter {
  NotificationRouter._();

  static Future<void> handleTap({
    required BuildContext context,
    required AppNotification notification,
  }) async {
    final type = notification.notificationType;
    final recordId = notification.navigationRecordId;

    debugPrint('[NotificationRouter] Tap: type=$type recordId=$recordId');

    try {
      switch (type) {
        case NotificationType.taskAssigned:
        case NotificationType.taskUpdated:
        case NotificationType.taskCompleted:
        case NotificationType.taskNotCompleted:
        case NotificationType.taskReassigned:
        case NotificationType.taskAttachmentAdded:
          await _navigateToTask(context, recordId ?? notification.taskId);
          break;

        case NotificationType.deliveryAssigned:
        case NotificationType.deliveryStarted:
        case NotificationType.deliveryPhotoUploaded:
        case NotificationType.materialDelivered:
        case NotificationType.materialDispatched:
          await _navigateToDispatch(context, recordId ?? notification.dispatchId);
          break;

        case NotificationType.customerCreated:
        case NotificationType.customerUpdated:
        case NotificationType.customerStageChanged:
        case NotificationType.loanStatusChanged:
        case NotificationType.paymentAdded:
        case NotificationType.paymentUpdated:
        case NotificationType.rtsUpdated:
        case NotificationType.subsidyUpdated:
          await _navigateToCustomer(context, recordId);
          break;

        case NotificationType.installationUpdated:
        case NotificationType.installationCompleted:
          await _navigateToCustomer(context, recordId);
          break;

        case NotificationType.testNotification:
        case NotificationType.systemAnnouncement:
        default:
          // No navigation for system-level notifications
          break;
      }
    } catch (e) {
      debugPrint('[NotificationRouter] Navigation error: $e');
      if (context.mounted) {
        _showRecordNotAvailable(context);
      }
    }
  }

  static Future<void> _navigateToTask(BuildContext context, String? taskId) async {
    if (taskId == null) {
      _showRecordNotAvailable(context);
      return;
    }
    // Navigate using Navigator — works with the existing single-route GoRouter setup
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TaskNotificationBridge(taskId: taskId),
      ),
    );
  }

  static Future<void> _navigateToDispatch(BuildContext context, String? dispatchId) async {
    if (dispatchId == null) {
      _showRecordNotAvailable(context);
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DispatchNotificationBridge(dispatchId: dispatchId),
      ),
    );
  }

  static Future<void> _navigateToCustomer(BuildContext context, String? customerId) async {
    if (customerId == null) {
      _showRecordNotAvailable(context);
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CustomerNotificationBridge(customerId: customerId),
      ),
    );
  }

  static void _showRecordNotAvailable(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Record is no longer available.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

// ─── Bridge Widgets ───────────────────────────────────────────────────────
// These load the actual detail screen lazily to avoid circular imports.

class _TaskNotificationBridge extends StatelessWidget {
  final String taskId;
  const _TaskNotificationBridge({required this.taskId});

  @override
  Widget build(BuildContext context) {
    // Lazy import to avoid circular deps
    return _LazyTaskDetails(taskId: taskId);
  }
}

class _LazyTaskDetails extends StatelessWidget {
  final String taskId;
  const _LazyTaskDetails({required this.taskId});

  @override
  Widget build(BuildContext context) {
    // Import at usage site to avoid circular dependency
    // The actual navigation is done by importing task_details_screen
    // This widget just pushes by name so no circular import is needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _TaskDetailLoader(taskId: taskId),
          ),
        );
      }
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// ignore: must_be_immutable
class _TaskDetailLoader extends StatelessWidget {
  final String taskId;
  // ignore: prefer_const_constructors_in_immutables
  _TaskDetailLoader({required this.taskId});

  @override
  Widget build(BuildContext context) {
    // We use a deferred import pattern by registering a builder function.
    // The actual TaskDetailsScreen is imported from the notification_service
    // via the registered route builder.
    return _NotificationNavigationRegistry.buildTaskDetails(context, taskId);
  }
}

class _DispatchNotificationBridge extends StatelessWidget {
  final String dispatchId;
  const _DispatchNotificationBridge({required this.dispatchId});

  @override
  Widget build(BuildContext context) {
    return _NotificationNavigationRegistry.buildDispatchDetails(context, dispatchId);
  }
}

class _CustomerNotificationBridge extends StatelessWidget {
  final String customerId;
  const _CustomerNotificationBridge({required this.customerId});

  @override
  Widget build(BuildContext context) {
    return _NotificationNavigationRegistry.buildCustomerDetails(context, customerId);
  }
}

// ─── Navigation Registry ──────────────────────────────────────────────────
/// Allows notification_router.dart to open screens without circular imports.
/// Screens register their builders at startup in notification_service.dart.
class _NotificationNavigationRegistry {
  static Widget Function(BuildContext, String)? _taskDetailsBuilder;
  static Widget Function(BuildContext, String)? _dispatchDetailsBuilder;
  static Widget Function(BuildContext, String)? _customerDetailsBuilder;

  static void registerTaskDetails(Widget Function(BuildContext, String) builder) {
    _taskDetailsBuilder = builder;
  }

  static void registerDispatchDetails(Widget Function(BuildContext, String) builder) {
    _dispatchDetailsBuilder = builder;
  }

  static void registerCustomerDetails(Widget Function(BuildContext, String) builder) {
    _customerDetailsBuilder = builder;
  }

  static Widget buildTaskDetails(BuildContext context, String taskId) {
    if (_taskDetailsBuilder != null) {
      return _taskDetailsBuilder!(context, taskId);
    }
    return const Scaffold(body: Center(child: Text('Task screen not available')));
  }

  static Widget buildDispatchDetails(BuildContext context, String dispatchId) {
    if (_dispatchDetailsBuilder != null) {
      return _dispatchDetailsBuilder!(context, dispatchId);
    }
    return const Scaffold(body: Center(child: Text('Dispatch screen not available')));
  }

  static Widget buildCustomerDetails(BuildContext context, String customerId) {
    if (_customerDetailsBuilder != null) {
      return _customerDetailsBuilder!(context, customerId);
    }
    return const Scaffold(body: Center(child: Text('Customer screen not available')));
  }
}

// Public alias for external registration
class NotificationNavigationRegistry {
  NotificationNavigationRegistry._();

  static void registerTaskDetails(Widget Function(BuildContext, String) builder) =>
      _NotificationNavigationRegistry.registerTaskDetails(builder);

  static void registerDispatchDetails(Widget Function(BuildContext, String) builder) =>
      _NotificationNavigationRegistry.registerDispatchDetails(builder);

  static void registerCustomerDetails(Widget Function(BuildContext, String) builder) =>
      _NotificationNavigationRegistry.registerCustomerDetails(builder);
}
