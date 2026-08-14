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
      await supabase.from('activity_log').insert({
        'customer_id': customerId,
        'action': action,
        'description': description,
        'performed_by': performedBy,
      });
      debugPrint('Logged activity: $description');
    } catch (e) {
      debugPrint('ActivityLogger error: $e');
    }
  }
}
