import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActivityLogger {
  static Future<void> log({
    required SupabaseClient supabase,
    required String? customerId,
    required String action,
    required String description,
    required String? performedBy,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      final effectiveUserId = (performedBy != null && performedBy.isNotEmpty)
          ? performedBy
          : user?.id;

      await supabase.from('activity_log').insert({
        'customer_id': (customerId != null && customerId.isNotEmpty) ? customerId : null,
        'action': action,
        'description': description,
        'performed_by': effectiveUserId,
      });
      debugPrint('[ActivityLogger] Logged activity: $description (User: $effectiveUserId)');
    } catch (e) {
      debugPrint('[ActivityLogger] Error logging activity: $e');
    }
  }
}
