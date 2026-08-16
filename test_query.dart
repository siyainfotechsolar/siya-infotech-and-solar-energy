import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
    'https://ldrvghqibwlzfxvvignu.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcnZnaHFpYndsemZ4dnZpZ251Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1NTA2MDYsImV4cCI6MjEwMjEyNjYwNn0.XrhMQo07mefgvyhIYFaA6BmgVXLdFlwZmQPHUWFjDRg'
  );

  try {
    final res = await supabase
        .from('tasks')
        .select('id, panel_serials, system_capacity')
        .limit(1);
    print('Query succeeded! Result: $res');
  } catch (e) {
    print('Query failed! Error: $e');
  }
  exit(0);
}
