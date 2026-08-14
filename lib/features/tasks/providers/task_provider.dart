import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';

class TaskListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final supabase = ref.watch(supabaseClientProvider);
    final user = ref.watch(currentUserProvider);
    
    if (user == null) return [];

    final role = await ref.watch(userRoleProvider.future);
    
    if (role == 'admin') {
      final response = await supabase
          .from('tasks')
          .select('*, customers(name, customer_id), creator:staff!created_by(name), task_staff(staff(name))')
          .order('created_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    } else {
      final response = await supabase
          .from('tasks')
          .select('*, customers(name, customer_id), creator:staff!created_by(name), task_staff!inner(staff_id), task_staff_list:task_staff(staff(name))')
          .eq('task_staff.staff_id', user.id)
          .order('created_at', ascending: false)
          .limit(100);
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
  
  // Fetch assigned staff names & photos
  try {
    final staffRes = await supabase
        .from('task_staff')
        .select('staff(name, profile_photo_url)')
        .eq('task_id', taskId);
    final assignedStaffList = (staffRes as List)
        .map((item) {
          final s = item['staff'] as Map<String, dynamic>?;
          return {
            'name': s?['name'] as String? ?? 'Unknown',
            'profile_photo_url': s?['profile_photo_url'] as String?,
          };
        })
        .toList();
    task['assigned_staff'] = assignedStaffList;
    task['assigned_staff_names'] = assignedStaffList.map((s) => s['name'] as String).toList();
  } catch (_) {
    task['assigned_staff'] = [];
    task['assigned_staff_names'] = [];
  }
  
  if (task['started_by'] != null) {
    final starterRes = await supabase.from('staff').select('name').eq('id', task['started_by']).maybeSingle();
    task['starter_name'] = starterRes?['name'];
  }
  if (task['completed_by'] != null) {
    final completerRes = await supabase.from('staff').select('name').eq('id', task['completed_by']).maybeSingle();
    task['completer_name'] = completerRes?['name'];
  }
  if (task['not_completed_by'] != null) {
    final workerRes = await supabase.from('staff').select('name').eq('id', task['not_completed_by']).maybeSingle();
    task['not_completed_by_name'] = workerRes?['name'];
  }

  // Fetch activity timeline
  try {
    final activityRes = await supabase
        .from('task_activity')
        .select('*, staff(name, profile_photo_url)')
        .eq('task_id', taskId)
        .order('created_at', ascending: true);
    task['activity'] = (activityRes as List).map((a) {
      final map = Map<String, dynamic>.from(a);
      final staffMap = map['staff'] as Map<String, dynamic>?;
      map['staff_name'] = staffMap?['name'] ?? 'Unknown Staff';
      map['staff_profile_photo_url'] = staffMap?['profile_photo_url'];
      return map;
    }).toList();
  } catch (_) {
    task['activity'] = [];
  }

  // Fetch task attachments
  try {
    final attachmentsRes = await supabase
        .from('task_attachments')
        .select('*, staff(name)')
        .eq('task_id', taskId)
        .order('created_at', ascending: false);
    task['attachments'] = (attachmentsRes as List).map((a) {
      final map = Map<String, dynamic>.from(a);
      final staffMap = map['staff'] as Map<String, dynamic>?;
      map['uploader_name'] = staffMap?['name'] ?? 'System';
      return map;
    }).toList();
  } catch (_) {
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
