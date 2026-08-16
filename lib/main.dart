import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/constants/supabase_constants.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/realtime_service.dart';
import 'core/widgets/global_loading_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    anonKey: SupabaseConstants.supabaseAnonKey,
  );

  // Initialize Firebase (one-time, before runApp)
  try {
    await Firebase.initializeApp();
    debugPrint('[main] Firebase initialized successfully.');
  } catch (e) {
    debugPrint('[main] Firebase init failed (google-services.json may be missing): $e');
    debugPrint('[main] App continues — in-app notifications still work via Supabase Realtime.');
  }

  runApp(
    const ProviderScope(
      child: SolarCrmApp(),
    ),
  );
}


class SolarCrmApp extends ConsumerWidget {
  const SolarCrmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    
    // Keep realtime service alive globally
    ref.watch(realtimeServiceProvider);

    return MaterialApp.router(
      title: 'Siya Solar Staff',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const GlobalLoadingOverlay(),
            const ConnectionBanner(),
          ],
        );
      },
    );
  }
}

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(connectionStatusProvider);
    if (isConnected) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.red.shade600,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.sync_problem, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Sync reconnecting...',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
