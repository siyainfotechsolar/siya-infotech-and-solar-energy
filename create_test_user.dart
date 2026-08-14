import 'package:supabase/supabase.dart';

// Please replace with your actual URL and ANON KEY from lib/core/constants/supabase_constants.dart
const supabaseUrl = 'https://ldrvghqibwlzfxvvignu.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcnZnaHFpYndsemZ4dnZpZ251Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1NTA2MDYsImV4cCI6MjEwMjEyNjYwNn0.XrhMQo07mefgvyhIYFaA6BmgVXLdFlwZmQPHUWFjDRg';

void main() async {
  print('Creating test user...');
  final supabase = SupabaseClient(supabaseUrl, supabaseKey);

  try {
    // 1. Sign up the user
    final response = await supabase.auth.signUp(
      email: 'admin@siyasolar.com',
      password: 'password123',
    );

    final user = response.user;
    if (user != null) {
      print('User created with ID: ${user.id}');

      // 2. Add them to the staff table as an admin
      await supabase.from('staff').insert({
        'id': user.id,
        'name': 'System Admin',
        'role': 'admin',
        'status': 'active'
      });

      print('Successfully added to staff table as admin!');
      print('\n--- LOGIN CREDENTIALS ---');
      print('Email: admin@siyasolar.com');
      print('Password: password123');
    } else {
      print('Failed to create user. Make sure Email confirmations are disabled in Supabase Auth settings.');
    }
  } catch (e, s) {
    print('Error: $e');
  }
}
