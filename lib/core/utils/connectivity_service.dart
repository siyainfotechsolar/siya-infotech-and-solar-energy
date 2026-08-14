import 'dart:io';
import 'package:flutter/foundation.dart';

class AppConnectivity {
  static Future<bool> isConnected() async {
    if (kIsWeb) return true; // dart:io socket/DNS is unsupported on Web

    // 1. Fast socket check to public DNS servers (bypasses domain DNS resolution)
    try {
      final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {}

    try {
      final socket = await Socket.connect('1.1.1.1', 53, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {}

    // 2. Multi-host DNS lookup fallback
    final hosts = [
      'google.com',
      'ldrvghqibwlzfxvvignu.supabase.co',
      'cloudflare.com',
      'supabase.com',
    ];

    for (final host in hosts) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }
}

