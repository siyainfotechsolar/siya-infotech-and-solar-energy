// Supabase project credentials.
// The publishable (anon) key is intentionally embedded in the app binary.
// It is safe to include here as long as:
//   1. Row Level Security (RLS) is enabled on all Supabase tables.
//   2. This file is NOT committed to a public Git repository.
class SupabaseConstants {
  static const String supabaseUrl = 'https://ldrvghqibwlzfxvvignu.supabase.co';

  // ignore: do_not_use_environment
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcnZnaHFpYndsemZ4dnZpZ251Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1NTA2MDYsImV4cCI6MjEwMjEyNjYwNn0.XrhMQo07mefgvyhIYFaA6BmgVXLdFlwZmQPHUWFjDRg';
}
