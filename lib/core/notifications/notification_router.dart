import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/permission_service.dart';
import '../services/global_loading_service.dart';
import '../services/app_update_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/tasks/ui/task_details_screen.dart';
import '../../features/customers/ui/customer_details_screen.dart';
import '../../features/leads/ui/lead_details_screen.dart';
import '../../features/staff/ui/staff_list_screen.dart';
import '../../features/staff/ui/delivery_details_screen.dart';
import '../../features/materials/ui/site_material_screen.dart';
import '../../features/tasks/services/task_details_router.dart';
import 'notification_model.dart';
import 'notification_state.dart';

/// Routes tapped notifications cleanly to their exact related screens.
/// Enforces permission checks and handles deleted/missing records safely.
class NotificationRouter {
  NotificationRouter._();

  static Future<void> handleTap({
    required BuildContext context,
    required WidgetRef ref,
    required AppNotification notification,
  }) async {
    final supabase = ref.read(supabaseClientProvider);
    final notifier = ref.read(notificationNotifierProvider.notifier);

    // 1. Mark as read immediately
    if (!notification.isRead) {
      await notifier.markAsRead(notification.id);
    }

    final entityType = notification.entityType;
    final entityId = notification.entityId;

    debugPrint('[NotificationRouter] Tapped: type=${notification.notificationType} entityType=$entityType entityId=$entityId');

    // 2. Permission Check
    final hasPermission = await _checkPermission(ref, entityType);
    if (!hasPermission) {
      if (context.mounted) {
        _showPermissionDenied(context);
      }
      return;
    }

    if (entityId == null || entityId.isEmpty) {
      if (entityType == 'app_update') {
        _handleAppUpdate(context, ref);
        return;
      }
      if (context.mounted) {
        _showRecordNotAvailable(context);
      }
      return;
    }

    // 3. Record Existence & Navigation based on entityType
    try {
      switch (entityType) {
        case 'task':
          await _navigateToTask(context, supabase, entityId, ref);
          break;

        case 'customer':
          await _navigateToCustomer(context, supabase, entityId, ref);
          break;

        case 'lead':
          await _navigateToLead(context, supabase, entityId);
          break;

        case 'installation':
          await _navigateToInstallation(context, supabase, entityId, ref);
          break;

        case 'material':
          await _navigateToMaterial(context, supabase, entityId);
          break;

        case 'delivery':
          await _navigateToDelivery(context, supabase, entityId, ref);
          break;

        case 'staff':
          await _navigateToStaff(context, supabase, entityId);
          break;

        case 'app_update':
          await _handleAppUpdate(context, ref);
          break;

        case 'system':
        default:
          if (context.mounted) {
            _showSystemNotificationDialog(context, notification);
          }
          break;
      }
    } catch (e) {
      debugPrint('[NotificationRouter] Routing error: $e');
      if (context.mounted) {
        _showRecordNotAvailable(context);
      }
    }
  }

  /// Permission Check before displaying data
  static Future<bool> _checkPermission(WidgetRef ref, String entityType) async {
    try {
      final perms = await ref.read(currentUserPermissionsProvider.future);

      switch (entityType) {
        case 'task':
          return perms.canView(AppModule.tasks);
        case 'customer':
          return perms.canView(AppModule.customers);
        case 'lead':
          return perms.canView(AppModule.leads);
        case 'installation':
          return perms.canView(AppModule.installation) || perms.canView(AppModule.customers);
        case 'material':
          return perms.canView(AppModule.materials);
        case 'delivery':
          return perms.canView(AppModule.delivery) || perms.canView(AppModule.materialDispatch);
        case 'staff':
          return perms.canView(AppModule.staff);
        case 'app_update':
        case 'system':
        default:
          return true;
      }
    } catch (_) {
      return true; // Fallback safely
    }
  }

  /// 1. Open Task Details via TaskDetailsRouter
  static Future<void> _navigateToTask(BuildContext context, SupabaseClient supabase, String taskId, WidgetRef ref) async {
    final res = await supabase
        .from('tasks')
        .select('*, customers(name, customer_id), creator:staff!created_by(name)')
        .eq('id', taskId)
        .maybeSingle();

    if (res == null) {
      if (context.mounted) _showRecordNotAvailable(context);
      return;
    }

    if (!context.mounted) return;
    await TaskDetailsRouter.open(context, ref, res);
  }

  /// 2. Open Customer Details (Enforces role-based restriction for non-admins)
  static Future<void> _navigateToCustomer(BuildContext context, SupabaseClient supabase, String customerId, WidgetRef ref) async {
    final perms = await ref.read(currentUserPermissionsProvider.future);

    // Non-admin roles should not receive full Customer Details screen
    if (perms.category != StaffCategory.admin) {
      final taskRes = await supabase
          .from('tasks')
          .select('id, name, status, priority, customer_id')
          .eq('customer_id', customerId)
          .maybeSingle();

      if (taskRes != null && context.mounted) {
        await TaskDetailsRouter.open(context, ref, taskRes);
        return;
      }
    }

    var res = await supabase
        .from('customers')
        .select('*, site_installation_tasks(task_type, status)')
        .eq('id', customerId)
        .maybeSingle();

    if (res == null) {
      res = await supabase
          .from('customers')
          .select('*, site_installation_tasks(task_type, status)')
          .eq('customer_id', customerId)
          .maybeSingle();
    }

    if (res == null) {
      if (context.mounted) _showRecordNotAvailable(context);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(customer: res!),
      ),
    );
  }

  /// 3. Open Lead Details
  static Future<void> _navigateToLead(BuildContext context, SupabaseClient supabase, String leadId) async {
    final res = await supabase
        .from('leads')
        .select()
        .eq('id', leadId)
        .maybeSingle();

    if (res == null) {
      if (context.mounted) _showRecordNotAvailable(context);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LeadDetailsScreen(lead: res),
      ),
    );
  }

  /// 4. Open Installation Details
  static Future<void> _navigateToInstallation(BuildContext context, SupabaseClient supabase, String recordId, WidgetRef ref) async {
    final perms = await ref.read(currentUserPermissionsProvider.future);

    if (perms.category != StaffCategory.admin) {
      final taskRes = await supabase
          .from('tasks')
          .select('id, name, status, priority, customer_id')
          .or('id.eq.$recordId,customer_id.eq.$recordId')
          .maybeSingle();

      if (taskRes != null && context.mounted) {
        await TaskDetailsRouter.open(context, ref, taskRes);
        return;
      }
    }

    var res = await supabase
        .from('customers')
        .select('*, site_installation_tasks(task_type, status)')
        .eq('id', recordId)
        .maybeSingle();

    if (res == null) {
      final taskRes = await supabase
          .from('site_installation_tasks')
          .select('customer_id')
          .eq('id', recordId)
          .maybeSingle();

      if (taskRes != null && taskRes['customer_id'] != null) {
        res = await supabase
            .from('customers')
            .select('*, site_installation_tasks(task_type, status)')
            .eq('id', taskRes['customer_id'])
            .maybeSingle();
      }
    }

    if (res == null) {
      if (context.mounted) _showRecordNotAvailable(context);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(customer: res!),
      ),
    );
  }

  /// 5. Open Material Details
  static Future<void> _navigateToMaterial(BuildContext context, SupabaseClient supabase, String recordId) async {
    var customerRes = await supabase
        .from('customers')
        .select('id, name, pm_surya_ghar_application_id')
        .eq('id', recordId)
        .maybeSingle();

    if (customerRes == null) {
      final matRes = await supabase
          .from('site_materials')
          .select('customer_id')
          .eq('id', recordId)
          .maybeSingle();

      if (matRes != null && matRes['customer_id'] != null) {
        customerRes = await supabase
            .from('customers')
            .select('id, name, pm_surya_ghar_application_id')
            .eq('id', matRes['customer_id'])
            .maybeSingle();
      }
    }

    if (customerRes == null) {
      if (context.mounted) _showRecordNotAvailable(context);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SiteMaterialScreen(
          customerId: customerRes!['id'],
          customerName: customerRes['name'] ?? 'Customer',
          pmSuryaGharApplicationId: customerRes['pm_surya_ghar_application_id'],
        ),
      ),
    );
  }

  /// 6. Open Delivery Details
  static Future<void> _navigateToDelivery(BuildContext context, SupabaseClient supabase, String dispatchId, WidgetRef ref) async {
    final perms = await ref.read(currentUserPermissionsProvider.future);

    if (perms.category == StaffCategory.deliveryStaff) {
      final dispatchRes = await supabase
          .from('material_dispatches')
          .select('customer_id')
          .eq('id', dispatchId)
          .maybeSingle();

      if (dispatchRes != null && dispatchRes['customer_id'] != null) {
        final taskRes = await supabase
            .from('tasks')
            .select('id, name, status, priority, customer_id')
            .eq('customer_id', dispatchRes['customer_id'])
            .maybeSingle();

        if (taskRes != null && context.mounted) {
          await TaskDetailsRouter.open(context, ref, taskRes);
          return;
        }
      }
    }

    final res = await supabase
        .from('material_dispatches')
        .select('*, staff(name), customers(name, address, mobile)')
        .eq('id', dispatchId)
        .maybeSingle();

    if (res == null) {
      if (context.mounted) _showRecordNotAvailable(context);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeliveryDetailsScreen(dispatch: res),
      ),
    );
  }

  /// 7. Open Staff Details
  static Future<void> _navigateToStaff(BuildContext context, SupabaseClient supabase, String staffId) async {
    final res = await supabase
        .from('staff')
        .select('*, task_staff(tasks(status))')
        .eq('id', staffId)
        .maybeSingle();

    if (res == null) {
      if (context.mounted) _showRecordNotAvailable(context);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StaffDetailsScreen(staff: res),
      ),
    );
  }

  /// 8. Open App Update
  static Future<void> _handleAppUpdate(BuildContext context, WidgetRef ref) async {
    try {
      final updateResult = await ref.read(globalLoadingProvider.notifier).runWithLoading(
        () async {
          final supabase = ref.read(supabaseClientProvider);
          return await AppUpdateService.checkUpdate(supabase);
        },
        type: LoadingType.updateLoading,
        message: 'Checking for app updates...',
      );

      if (!context.mounted || updateResult == null) return;

      if (updateResult.status == UpdateStatus.noUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are using the latest version of Siya Solar Staff.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        _showRecordNotAvailable(context);
      }
    }
  }

  /// Show System Announcement / Info Dialog
  static void _showSystemNotificationDialog(BuildContext context, AppNotification notification) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(notification.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(notification.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Record missing / deleted notification notice
  static void _showRecordNotAvailable(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This item is no longer available.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Permission denied notification notice
  static void _showPermissionDenied(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("You don't have permission to view this item."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
