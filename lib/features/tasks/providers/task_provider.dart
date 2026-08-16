import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/permission_service.dart';


class TaskListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final supabase = ref.watch(supabaseClientProvider);
    final user = ref.watch(currentUserProvider);
    
    if (user == null) return [];

    final perms = await ref.watch(currentUserPermissionsProvider.future);
    
    if (perms.category == StaffCategory.admin ||
        perms.dataAccessLevel == DataAccessLevel.allData ||
        perms.dataAccessLevel == DataAccessLevel.teamData) {
      final response = await supabase
          .from('tasks')
          .select('*, customers(name, customer_id), creator:staff!created_by(name), task_staff(staff(name))')
          .order('created_at', ascending: false)
          .limit(500);
      return List<Map<String, dynamic>>.from(response);
    } else {
      final response = await supabase
          .from('tasks')
          .select('*, customers(name, customer_id), creator:staff!created_by(name), task_staff!inner(staff_id), task_staff_list:task_staff(staff(name))')
          .eq('task_staff.staff_id', user.id)
          .order('created_at', ascending: false)
          .limit(500);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<void> upsertTask(String id) async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);
      if (user == null) return;
      final role = await ref.read(userRoleProvider.future);

      dynamic response;
      if (role == 'admin') {
        response = await supabase
            .from('tasks')
            .select('*, customers(name, customer_id), creator:staff!created_by(name), task_staff(staff(name))')
            .eq('id', id)
            .single();
      } else {
        response = await supabase
            .from('tasks')
            .select('*, customers(name, customer_id), creator:staff!created_by(name), task_staff!inner(staff_id), task_staff_list:task_staff(staff(name))')
            .eq('task_staff.staff_id', user.id)
            .eq('id', id)
            .single();
      }
      
      if (state.value != null) {
        final current = List<Map<String, dynamic>>.from(state.value!);
        final idx = current.indexWhere((t) => t['id'] == id);
        if (idx >= 0) {
          current[idx] = response;
        } else {
          current.insert(0, response);
        }
        state = AsyncData(current);
      }
    } catch (e) {
      // Ignored
    }
  }

  void removeTask(String id) {
    if (state.value != null) {
      final current = state.value!.where((t) => t['id'] != id).toList();
      state = AsyncData(current);
    }
  }
}

final taskListProvider = AsyncNotifierProvider<TaskListNotifier, List<Map<String, dynamic>>>(TaskListNotifier.new);

// Single Task details provider with worker names resolved
final taskDetailsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, taskId) async {
  final supabase = ref.watch(supabaseClientProvider);
  final res = await supabase
      .from('tasks')
      .select('*, customers(*), creator:staff!created_by(name, profile_photo_url)')
      .eq('id', taskId)
      .single();

  final task = Map<String, dynamic>.from(res);

  final startedBy = task['started_by'] as String?;
  final completedBy = task['completed_by'] as String?;
  final notCompletedBy = task['not_completed_by'] as String?;

  // Run secondary detail queries in parallel
  late final List<dynamic> results;
  try {
    results = await Future.wait([
      supabase.from('task_staff').select('staff(name, profile_photo_url)').eq('task_id', taskId),
      startedBy != null ? supabase.from('staff').select('name').eq('id', startedBy).maybeSingle() : Future.value(null),
      completedBy != null ? supabase.from('staff').select('name').eq('id', completedBy).maybeSingle() : Future.value(null),
      notCompletedBy != null ? supabase.from('staff').select('name').eq('id', notCompletedBy).maybeSingle() : Future.value(null),
      supabase.from('task_activity').select('*, staff(name, profile_photo_url)').eq('task_id', taskId).order('created_at', ascending: true),
      supabase.from('task_attachments').select('*, staff(name)').eq('task_id', taskId).order('created_at', ascending: false),
    ]);
  } catch (e) {
    results = [null, null, null, null, null, null];
  }

  // 1. Process staff
  final staffRes = results[0];
  if (staffRes != null && staffRes is List) {
    final assignedStaffList = staffRes.map((item) {
      final s = item['staff'] as Map<String, dynamic>?;
      return {
        'name': s?['name'] as String? ?? 'Unknown',
        'profile_photo_url': s?['profile_photo_url'] as String?,
      };
    }).toList();
    task['assigned_staff'] = assignedStaffList;
    task['assigned_staff_names'] = assignedStaffList.map((s) => s['name'] as String).toList();
  } else {
    task['assigned_staff'] = [];
    task['assigned_staff_names'] = [];
  }

  // 2. Process names
  if (results[1] != null && results[1] is Map) task['starter_name'] = (results[1] as Map)['name'];
  if (results[2] != null && results[2] is Map) task['completer_name'] = (results[2] as Map)['name'];
  if (results[3] != null && results[3] is Map) task['not_completed_by_name'] = (results[3] as Map)['name'];

  // 3. Process activity
  final activityRes = results[4];
  if (activityRes != null && activityRes is List) {
    task['activity'] = activityRes.map((a) {
      final map = Map<String, dynamic>.from(a);
      final staffMap = map['staff'] as Map<String, dynamic>?;
      map['staff_name'] = staffMap?['name'] ?? 'Unknown Staff';
      map['staff_profile_photo_url'] = staffMap?['profile_photo_url'];
      return map;
    }).toList();
  } else {
    task['activity'] = [];
  }

  // 4. Process attachments
  final attachmentsRes = results[5];
  if (attachmentsRes != null && attachmentsRes is List) {
    task['attachments'] = attachmentsRes.map((a) {
      final map = Map<String, dynamic>.from(a);
      final staffMap = map['staff'] as Map<String, dynamic>?;
      map['uploader_name'] = staffMap?['name'] ?? 'System';
      return map;
    }).toList();
  } else {
    task['attachments'] = [];
  }

  return task;
});

final incompleteTaskListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  
  final role = await ref.watch(userRoleProvider.future);
  
  if (role == 'admin' || role == 'supervisor') {
    final response = await supabase
        .from('tasks')
        .select('*, customers(name, customer_id, mobile, pm_surya_ghar_application_id), creator:staff!created_by(name), task_staff(staff(id, name, profile_photo_url))')
        .eq('status', 'not_completed')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  } else {
    final response = await supabase
        .from('tasks')
        .select('*, customers(name, customer_id, mobile, pm_surya_ghar_application_id), creator:staff!created_by(name), task_staff!inner(staff_id), task_staff_list:task_staff(staff(id, name, profile_photo_url))')
        .eq('status', 'not_completed')
        .eq('task_staff.staff_id', user.id)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }
});
