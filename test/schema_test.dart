import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:solar_crm/core/constants/supabase_constants.dart';

void main() {
  test('Check schema', () async {
    final supabase = SupabaseClient(SupabaseConstants.supabaseUrl, SupabaseConstants.supabaseAnonKey);
    print("--- TASKS COLUMNS ---");
    try {
      final tasks = await supabase.from('tasks').select('*').limit(1);
      if (tasks.isNotEmpty) {
        print(tasks.first.keys.toList());
      } else {
        print("Tasks table is empty");
      }
    } catch(e) {
      print("Error tasks: $e");
    }

    print("--- TASK TYPES ---");
    try {
      final taskTypes = await supabase.from('task_types').select('*').limit(1);
      if (taskTypes.isNotEmpty) {
        print(taskTypes.first.keys.toList());
      } else {
        print("Task types table is empty");
      }
    } catch(e) {
      print("Error task_types: $e");
    }
  });
}
