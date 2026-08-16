import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'permission_service.dart';

/// Central Data Filter Service for enforcing Data Access Levels & Role Scoping across Supabase queries.
class DataFilterService {

  /// Columns allowed for non-admin staff (Strictly excludes financial & administrative secrets)
  static const String safeCustomerColumns = '''
    id, customer_id, name, mobile, consumer_number, village, address, system_size, stage, priority, created_at, updated_at
  ''';

  /// Select columns string based on user permissions
  static String selectCustomerFields(StaffPermissions permissions) {
    if (permissions.category == StaffCategory.admin) {
      return '*';
    }
    return safeCustomerColumns;
  }

  /// Retrieves customer IDs that an assigned staff member is authorized to view.
  /// Used for search filtering and role-based data scoping.
  static Future<List<String>> getAuthorizedCustomerIds({
    required SupabaseClient supabase,
    required String userId,
    required StaffPermissions permissions,
  }) async {
    if (permissions.category == StaffCategory.admin ||
        permissions.dataAccessLevel == DataAccessLevel.allData ||
        permissions.dataAccessLevel == DataAccessLevel.teamData) {
      return []; // Empty list indicates no customer ID restriction (all allowed for Admin/Supervisor)
    }

    try {
      final customerIds = <String>{};

      // 1. Fetch customers from assigned tasks in task_staff
      final taskRes = await supabase
          .from('task_staff')
          .select('tasks(customer_id)')
          .eq('staff_id', userId);

      if (taskRes is List) {
        for (final item in taskRes) {
          final cid = (item['tasks'] as Map?)?['customer_id'] as String?;
          if (cid != null && cid.isNotEmpty) {
            customerIds.add(cid);
          }
        }
      }

      // 2. Fetch customers from assigned material dispatches (Delivery Staff)
      if (permissions.category == StaffCategory.deliveryStaff || permissions.category == StaffCategory.otherStaff) {
        final dispatchRes = await supabase
            .from('material_dispatches')
            .select('customer_id')
            .eq('delivery_staff_id', userId);

        if (dispatchRes is List) {
          for (final item in dispatchRes) {
            final cid = item['customer_id'] as String?;
            if (cid != null && cid.isNotEmpty) {
              customerIds.add(cid);
            }
          }
        }
      }

      // 3. Fetch customers from site installation tasks (Structure Installer / Wireman)
      if (permissions.category == StaffCategory.structureInstaller || permissions.category == StaffCategory.wireman) {
        final instRes = await supabase
            .from('site_installation_tasks')
            .select('customer_id')
            .or('started_by.eq.$userId,completed_by.eq.$userId');

        if (instRes is List) {
          for (final item in instRes) {
            final cid = item['customer_id'] as String?;
            if (cid != null && cid.isNotEmpty) {
              customerIds.add(cid);
            }
          }
        }
      }

      return customerIds.toList();
    } catch (e) {
      debugPrint('[DataFilterService] Error fetching authorized customer IDs: $e');
      return [];
    }
  }

  /// Retrieves task IDs that an assigned staff member is authorized to view.
  static Future<List<String>> getAuthorizedTaskIds({
    required SupabaseClient supabase,
    required String userId,
    required StaffPermissions permissions,
  }) async {
    if (permissions.category == StaffCategory.admin ||
        permissions.dataAccessLevel == DataAccessLevel.allData ||
        permissions.dataAccessLevel == DataAccessLevel.teamData) {
      return []; // All allowed for Admin / Supervisor
    }

    try {
      final assignedRes = await supabase
          .from('task_staff')
          .select('task_id')
          .eq('staff_id', userId);

      if (assignedRes is List) {
        return assignedRes
            .map((e) => e['task_id'] as String?)
            .whereType<String>()
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[DataFilterService] Error fetching authorized task IDs: $e');
      return [];
    }
  }
}
