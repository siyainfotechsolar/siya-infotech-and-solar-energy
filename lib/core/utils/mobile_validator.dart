import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MobileValidator {
  MobileValidator._();

  /// Regex for valid Indian 10-digit mobile number (starts with 6, 7, 8, or 9)
  static final RegExp _indianMobileRegExp = RegExp(r'^[6-9][0-9]{9}$');

  /// Input formatters for mobile text fields (digits only, max 10 digits)
  static List<TextInputFormatter> get inputFormatters => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ];

  /// Normalizes any input phone string to clean 10-digit format (e.g. "+91 98765-43210" -> "9876543210")
  static String normalize(String? mobile) {
    if (mobile == null) return '';
    // Strip non-digits
    String digits = mobile.replaceAll(RegExp(r'\D'), '');
    // If starts with 91 and has 12 digits, strip country code 91
    if (digits.startsWith('91') && digits.length == 12) {
      digits = digits.substring(2);
    }
    // If starts with 0 and has 11 digits, strip leading 0
    if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    return digits;
  }

  /// Form Field Validator for Indian Mobile Numbers
  static String? validate(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      if (required) return 'Mobile number is required.';
      return null;
    }

    final clean = normalize(value.trim());

    if (clean.length < 10) {
      return 'Mobile number must be 10 digits.';
    }

    if (clean.length > 10) {
      return 'Mobile number cannot exceed 10 digits.';
    }

    if (!_indianMobileRegExp.hasMatch(clean)) {
      return 'Enter a valid Indian mobile number.';
    }

    return null;
  }

  /// Check if mobile number already exists in specified database table
  static Future<Map<String, dynamic>?> checkDuplicate({
    required SupabaseClient client,
    required String table,
    required String mobile,
    String? excludeId,
  }) async {
    final cleanMobile = normalize(mobile);
    if (cleanMobile.length != 10) return null;

    try {
      var query = client.from(table).select().eq('mobile', cleanMobile);
      if (excludeId != null && excludeId.isNotEmpty) {
        query = query.neq('id', excludeId);
      }
      final res = await query.maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }
}
