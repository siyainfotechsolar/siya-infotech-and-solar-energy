import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';

final pendingTaskCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;

  try {
    // 1. Fetch task IDs assigned to the logged-in staff member
    final assignedRes = await supabase
        .from('task_staff')
        .select('task_id')
        .eq('staff_id', user.id);

    final taskIds = (assignedRes as List)
        .map((e) => e['task_id'] as String?)
        .whereType<String>()
        .toList();

    if (taskIds.isEmpty) return 0;

    // 2. Query tasks with status = PENDING (case-insensitive) assigned to this staff member
    final pendingRes = await supabase
        .from('tasks')
        .select('id')
        .inFilter('id', taskIds)
        .ilike('status', 'pending');

    return (pendingRes as List).length;
  } catch (_) {
    return 0;
  }
});
