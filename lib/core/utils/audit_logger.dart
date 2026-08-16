import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditLogger {
  static Future<void> log({
    required SupabaseClient supabase,
    required String? userId,
    required String action,
    required String module,
    String? entityId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await supabase.from('audit_logs').insert({
        'user_id': userId,
        'action': action,
        'module': module,
        'entity_id': entityId,
        'details': details ?? {},
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint('[AuditLogger] Logged action "$action" in module "$module" by user "$userId"');
    } catch (e) {
      debugPrint('[AuditLogger] Failed to write audit log: $e');
    }
  }
}
