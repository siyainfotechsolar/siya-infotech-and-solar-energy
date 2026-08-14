import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/connectivity_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/ui/login_screen.dart';
import '../../features/auth/ui/splash_screen.dart';
import '../../features/home/ui/admin_dashboard_screen.dart';
import '../../features/home/ui/staff_dashboard_screen.dart';
import '../config/app_version_config.dart';
import '../notifications/notification_service.dart';
import '../notifications/notification_state.dart';
import '../notifications/notification_repository.dart';

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  static bool hasPromptedNormalUpdateThisSession = false;

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _isCheckingInternet = true;
  bool _hasInternet = true;
  bool _isCheckingVersion = true;
  bool _needsForceUpdate = false;
  bool _showNormalUpdatePrompt = false;
  Map<String, dynamic>? _updateConfig;

  @override
  void initState() {
    super.initState();
    _checkVersionAndAuth();
  }

  Future<void> _checkVersionAndAuth() async {
    await _checkInternet();
    if (_showNormalUpdatePrompt && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNormalUpdateDialog();
      });
    }
  }

  bool _isVersionLessThan(String current, String target) {
    try {
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final targetParts = target.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      for (var i = 0; i < 3; i++) {
        final currentPart = currentParts.length > i ? currentParts[i] : 0;
        final targetPart = targetParts.length > i ? targetParts[i] : 0;
        if (currentPart < targetPart) return true;
        if (currentPart > targetPart) return false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _checkInternet() async {
    setState(() {
      _isCheckingInternet = true;
      _isCheckingVersion = true;
    });
    
    final isConnected = await AppConnectivity.isConnected();
    if (!isConnected) {
      if (mounted) {
        setState(() {
          _hasInternet = false;
          _isCheckingInternet = false;
          _isCheckingVersion = false;
        });
      }
      return;
    }

    try {
      final supabase = ref.read(supabaseClientProvider);
      final updateConfig = await supabase.from('app_updates').select().eq('id', 1).maybeSingle();
      if (updateConfig != null) {
        final latest = updateConfig['latest_version'] as String;
        final minSupported = updateConfig['minimum_supported_version'] as String;
        const current = AppVersionConfig.version;

        if (_isVersionLessThan(current, minSupported)) {
          _needsForceUpdate = true;
          _updateConfig = updateConfig;
        } else if (_isVersionLessThan(current, latest)) {
          if (!AuthWrapper.hasPromptedNormalUpdateThisSession) {
            _showNormalUpdatePrompt = true;
            _updateConfig = updateConfig;
          }
        }
      }
    } catch (_) {
      // Fail safely on error
    } finally {
      if (mounted) {
        setState(() {
          _hasInternet = true;
          _isCheckingInternet = false;
          _isCheckingVersion = false;
        });
      }
    }
  }

  void _showNormalUpdateDialog() {
    final latestVersion = _updateConfig?['latest_version'] ?? 'N/A';
    final notes = _updateConfig?['release_notes'] ?? 'Performance improvements and bug fixes.';
    final updateUrl = _updateConfig?['update_url'] ?? '';

    AuthWrapper.hasPromptedNormalUpdateThisSession = true;
    setState(() {
      _showNormalUpdatePrompt = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('NEW VERSION AVAILABLE', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version $latestVersion is now available.', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('What\'s new:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(notes),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () async {
                final url = Uri.parse(updateUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('UPDATE NOW'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingInternet || _isCheckingVersion) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_needsForceUpdate) {
      final requiredVersion = _updateConfig?['minimum_supported_version'] ?? 'N/A';
      final updateUrl = _updateConfig?['update_url'] ?? '';
      
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update_alt, size: 80, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'UPDATE REQUIRED',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your app version is no longer supported. Please update the application to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Current Version: ${AppVersionConfig.version}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Required: $requiredVersion',
                      style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final url = Uri.parse(updateUrl);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('UPDATE NOW'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!_hasInternet) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No Internet Connection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Please check your connection and try again.'),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _checkVersionAndAuth, child: const Text('RETRY')),
            ],
          ),
        ),
      );
    }

    final authStateAsync = ref.watch(authStateProvider);

    return authStateAsync.when(
      data: (authState) {
        final session = authState.session;
        if (session == null) {
          // User logged out — clean up notification state
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(notificationNotifierProvider.notifier).clear();
          });
          return const LoginScreen();
        }

        final userId = session.user.id;
        final roleAsync = ref.watch(userRoleProvider);

        return roleAsync.when(
          data: (role) {
            // Initialize notification service when user is authenticated and role is known
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              final repo = ref.read(notificationRepositoryProvider);
              final notifier = ref.read(notificationNotifierProvider.notifier);
              // Set singleton for sendNotification helper
              NotificationSender.setInstance(repo);
              // Initialize service (Firebase + local notifications)
              await notificationService.initialize(repo: repo, notifier: notifier);
              // Request permission and register device token
              await notificationService.requestPermission();
              await notificationService.registerDeviceToken(userId);
              // Load notifications and subscribe to realtime
              final supabase = ref.read(supabaseClientProvider);
              await notifier.initialize(supabase, userId);
            });

            if (role == 'admin') return const AdminDashboardScreen();
            if (role == 'office_staff') return const StaffDashboardScreen();
            
            // If they are logged in but have no role (e.g. newly created user), wait.
            return const Scaffold(body: Center(child: Text('Account pending activation...')));
          },
          loading: () => const SplashScreen(),
          error: (e, _) => Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Failed to load user role'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      final supabase = ref.read(supabaseClientProvider);
                      // Clean up notifications on forced logout
                      ref.read(notificationNotifierProvider.notifier).clear();
                      notificationService.removeDeviceToken(userId);
                      supabase.auth.signOut();
                    }, 
                    child: const Text('LOGOUT & RETRY')
                  )
                ],
              )
            ),
          ),
        );
      },
      loading: () => const SplashScreen(),
      error: (e, _) => Scaffold(body: Center(child: Text('Auth Error: $e'))),
    );
  }
}
