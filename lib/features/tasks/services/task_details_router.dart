import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/permission_service.dart';
import '../ui/task_details_screen.dart';
import '../ui/delivery_task_details_screen.dart';
import '../ui/structure_task_details_screen.dart';
import '../ui/wireman_task_details_screen.dart';
import '../ui/supervisor_task_details_screen.dart';

/// Central Task Details Router
/// Enforces role-specific Task Details screens and prevents staff members
/// from opening full Customer Details or sensitive Admin screens.
class TaskDetailsRouter {
  TaskDetailsRouter._();

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> task,
  ) async {
    final permissions = await ref.read(currentUserPermissionsProvider.future);
    final category = permissions.category;

    Widget targetScreen;

    switch (category) {
      case StaffCategory.deliveryStaff:
        targetScreen = DeliveryTaskDetailsScreen(task: task);
        break;

      case StaffCategory.structureInstaller:
        targetScreen = StructureTaskDetailsScreen(task: task);
        break;

      case StaffCategory.wireman:
        targetScreen = WiremanTaskDetailsScreen(task: task);
        break;

      case StaffCategory.supervisor:
        targetScreen = SupervisorTaskDetailsScreen(task: task);
        break;

      case StaffCategory.admin:
      default:
        targetScreen = TaskDetailsScreen(task: task);
        break;
    }

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => targetScreen),
      );
    }
  }

  static Widget getWidgetForRole({
    required StaffPermissions permissions,
    required Map<String, dynamic> task,
  }) {
    switch (permissions.category) {
      case StaffCategory.deliveryStaff:
        return DeliveryTaskDetailsScreen(task: task);
      case StaffCategory.structureInstaller:
        return StructureTaskDetailsScreen(task: task);
      case StaffCategory.wireman:
        return WiremanTaskDetailsScreen(task: task);
      case StaffCategory.supervisor:
        return SupervisorTaskDetailsScreen(task: task);
      case StaffCategory.admin:
      default:
        return TaskDetailsScreen(task: task);
    }
  }
}
