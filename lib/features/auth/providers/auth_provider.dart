import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_version_config.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return supabase.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider).value;
  return authState?.session?.user;
});

String? _lastUpdatedStaffUserId;

final userRoleProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    _lastUpdatedStaffUserId = null;
    return null;
  }
  
  final supabase = ref.watch(supabaseClientProvider);

  // Background update staff version tracking fields only once per session
  if (_lastUpdatedStaffUserId != user.id) {
    _lastUpdatedStaffUserId = user.id;
    try {
      supabase.from('staff').update({
        'app_version': AppVersionConfig.version,
        'build_number': AppVersionConfig.buildNumber,
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id).then((_) => null);
    } catch (_) {
      // Ignore background log errors
    }
  }

  final response = await supabase
      .from('staff')
      .select('role, status')
      .eq('id', user.id)
      .maybeSingle();
      
  if (response == null || response['status'] != 'active') {
    return null;
  }
  return response['role'] as String?;
});

final currentStaffProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final supabase = ref.watch(supabaseClientProvider);
  return await supabase
      .from('staff')
      .select('*')
      .eq('id', user.id)
      .maybeSingle();
});
