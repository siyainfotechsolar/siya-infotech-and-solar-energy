import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/connectivity_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/ui/login_screen.dart';
import '../../features/auth/ui/splash_screen.dart';
import '../../features/home/ui/admin_dashboard_screen.dart';
import '../../features/home/ui/staff_dashboard_screen.dart';
import '../services/app_update_service.dart';
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
  AppReleaseInfo? _activeRelease;

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
      final updateResult = await AppUpdateService.checkUpdate(supabase);
      if (updateResult.status == UpdateStatus.mandatoryUpdate) {
        _needsForceUpdate = true;
        _activeRelease = updateResult.release;
      } else if (updateResult.status == UpdateStatus.optionalUpdate) {
        if (!AuthWrapper.hasPromptedNormalUpdateThisSession) {
          _showNormalUpdatePrompt = true;
          _activeRelease = updateResult.release;
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
    final release = _activeRelease;
    if (release == null) return;

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
          title: const Text('NEW UPDATE AVAILABLE', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Latest Version:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
              Text(release.latestVersion, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              if (release.releaseNotes.isNotEmpty) ...[
                const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(release.releaseNotes),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final url = Uri.parse(release.apkDownloadUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
              child: const Text('UPDATE NOW'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('LATER'),
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

    if (_needsForceUpdate && _activeRelease != null) {
      final release = _activeRelease!;
      
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
                    const SizedBox(height: 16),
                    const Text('Latest Version:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                    Text(release.latestVersion, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 12),
                    if (release.releaseNotes.isNotEmpty) ...[
                      const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(release.releaseNotes, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                    ],
                    ElevatedButton(
                      onPressed: () async {
                        final url = Uri.parse(release.apkDownloadUrl);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('UPDATE NOW'),
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
            // Safe background initialization for notifications without blocking app UI
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              try {
                final repo = ref.read(notificationRepositoryProvider);
                final notifier = ref.read(notificationNotifierProvider.notifier);
                NotificationSender.setInstance(repo);
                await notificationService.initialize(repo: repo, notifier: notifier).timeout(const Duration(seconds: 8));
                await notificationService.requestPermission().timeout(const Duration(seconds: 5));
                await notificationService.registerDeviceToken(userId).timeout(const Duration(seconds: 5));
                final supabase = ref.read(supabaseClientProvider);
                await notifier.initialize(supabase, userId).timeout(const Duration(seconds: 8));
              } catch (e) {
                debugPrint('AuthWrapper: Notification initialization skipped/failed safely: $e');
              }
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
