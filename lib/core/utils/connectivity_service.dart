import 'dart:io';
import 'package:flutter/foundation.dart';

class AppConnectivity {
  static Future<bool> isConnected() async {
    if (kIsWeb) return true; // dart:io InternetAddress.lookup is unsupported on Web
    
    try {
      final result = await InternetAddress.lookup('supabase.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
