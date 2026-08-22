import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_version_config.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/global_loading_service.dart';

import '../../auth/providers/auth_provider.dart';
import '../../leads/ui/lead_list_screen.dart';
import '../../staff/ui/staff_list_screen.dart';
import '../../staff/ui/staff_directory_screen.dart';
import '../../import/ui/import_screen.dart';
import '../../customers/ui/customer_merge_screen.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../tasks/ui/unassigned_tasks_screen.dart';
import 'audit_log_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(userRoleProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
      body: ListView(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.blue.shade50),
            accountName: roleAsync.when(
              data: (role) => Text('Role: ${role?.toUpperCase() ?? 'Unknown'}', style: const TextStyle(color: Colors.black)),
              loading: () => const Text('Loading...', style: TextStyle(color: Colors.black)),
              error: (_, _) => const Text('Error', style: TextStyle(color: Colors.black)),
            ),
            accountEmail: Text(user?.email ?? '', style: const TextStyle(color: Colors.black54)),
            currentAccountPicture: ref.watch(currentStaffProfileProvider).when(
              loading: () => const CircleAvatar(
                backgroundColor: Colors.blue,
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              ),
              error: (_, _) => const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.person, color: Colors.white, size: 40),
              ),
              data: (profile) {
                final photoUrl = profile?['profile_photo_url'] as String?;
                final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
                final name = profile?['name'] ?? 'Staff';
                return CircleAvatar(
                  backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                  backgroundColor: hasPhoto ? Colors.transparent : Colors.blue,
                  child: hasPhoto
                      ? null
                      : Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'S',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                );
              },
            ),
          ),
          
          // --- Common Items ---
          ListTile(
            leading: const Icon(Icons.contact_phone),
            title: const Text('Employee Directory'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const StaffDirectoryScreen()));
            },
          ),
          roleAsync.when(
            data: (role) {
              if (role != 'installer') {
                return ListTile(
                  leading: const Icon(Icons.leaderboard),
                  title: const Text('Leads'),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LeadListScreen()));
                  },
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          
          // --- Admin Only Items ---
          roleAsync.when(
            data: (role) {
              if (role == 'admin') {
                return Column(
                  children: [
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Align(alignment: Alignment.centerLeft, child: Text('Admin Tools', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                    ),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts),
                      title: const Text('Staff Management'),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const StaffListScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Materials & Dispatches'),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerListScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.assignment_ind_outlined),
                      title: const Text('Unassigned Tasks'),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const UnassignedTasksScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.merge_type),
                      title: const Text('Customer Merge'),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerMergeScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.history_toggle_off),
                      title: const Text('Activity History & Audit Log'),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const AuditLogScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.upload_file),
                      title: const Text('Data Import'),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ImportScreen()));
                      },
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'About',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App Version'),
            subtitle: Text('${AppVersionConfig.version} (Build ${AppVersionConfig.buildNumber})'),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Check for Updates'),
            onTap: () => _checkForUpdates(context, ref),
          ),

          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final supabase = ref.read(supabaseClientProvider);
              await supabase.auth.signOut();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    try {
      final updateResult = await ref.read(globalLoadingProvider.notifier).runWithLoading(
        () async {
          final supabase = ref.read(supabaseClientProvider);
          return await AppUpdateService.checkUpdate(supabase);
        },
        type: LoadingType.updateLoading,
        message: 'Checking for updates...',
      );
      
      if (!context.mounted || updateResult == null) return;
      
      if (updateResult.status == UpdateStatus.noUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are using the latest version.')),
        );
        return;
      }

      final release = updateResult.release;
      if (release == null) return;
      
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(updateResult.status == UpdateStatus.mandatoryUpdate ? 'UPDATE REQUIRED' : 'NEW UPDATE AVAILABLE', style: const TextStyle(fontWeight: FontWeight.bold)),
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
              if (updateResult.status != UpdateStatus.mandatoryUpdate)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('LATER'),
                ),
            ],
          );
        },
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to check for updates.')),
        );
      }
    }
  }
}
