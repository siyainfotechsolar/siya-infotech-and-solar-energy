import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/permission_service.dart';
import '../ui/task_details_screen.dart';
import '../ui/simple_task_details_screen.dart';

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
      case StaffCategory.admin:
        targetScreen = TaskDetailsScreen(task: task);
        break;

      default:
        // All staff categories (supervisor, wireman, installer, delivery, other, office)
        // use the unified simple task details screen.
        targetScreen = SimpleTaskDetailsScreen(task: task);
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
      case StaffCategory.admin:
        return TaskDetailsScreen(task: task);
      default:
        return SimpleTaskDetailsScreen(task: task);
    }
  }
}
