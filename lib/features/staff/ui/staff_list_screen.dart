import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' as io;
import '../../../core/utils/date_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customers/ui/customer_details_screen.dart';
import '../../tasks/ui/task_details_screen.dart';
import 'add_staff_screen.dart';

// ─── Staff Filter ────────────────────────────────────────────────────────────
class StaffFilter {
  final String query;
  final String role;
  final String status;

  StaffFilter({this.query = '', this.role = 'All', this.status = 'All'});

  StaffFilter copyWith({String? query, String? role, String? status}) {
    return StaffFilter(
      query: query ?? this.query,
      role: role ?? this.role,
      status: status ?? this.status,
    );
  }
}

class StaffFilterNotifier extends Notifier<StaffFilter> {
  @override
  StaffFilter build() => StaffFilter();

  void updateFilter(StaffFilter filter) => state = filter;
}

final staffFilterProvider = NotifierProvider<StaffFilterNotifier, StaffFilter>(StaffFilterNotifier.new);

// ─── Staff List Notifier ─────────────────────────────────────────────────────
class StaffListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final supabase = ref.watch(supabaseClientProvider);
    final filter = ref.watch(staffFilterProvider);
    
    var queryBuilder = supabase
        .from('staff')
        .select('*, task_staff(tasks(status))');

    if (filter.query.isNotEmpty) {
      queryBuilder = queryBuilder.or('name.ilike.%${filter.query}%,mobile.ilike.%${filter.query}%,role.ilike.%${filter.query}%');
    }
    if (filter.role != 'All') {
      queryBuilder = queryBuilder.eq('role', filter.role);
    }
    if (filter.status != 'All') {
      queryBuilder = queryBuilder.eq('status', filter.status);
    }

    final response = await queryBuilder.order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> upsertStaff(String id) async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final response = await supabase
          .from('staff')
          .select('*, task_staff(tasks(status))')
          .eq('id', id)
          .single();
          
      if (state.value != null) {
        final current = List<Map<String, dynamic>>.from(state.value!);
        final idx = current.indexWhere((s) => s['id'] == id);
        if (idx >= 0) {
          current[idx] = response;
        } else {
          current.insert(0, response);
        }
        state = AsyncData(current);
      }
    } catch (e) {
      // Ignored
    }
  }

  void removeStaff(String id) {
    if (state.value != null) {
      final current = state.value!.where((s) => s['id'] != id).toList();
      state = AsyncData(current);
    }
  }
}

final staffListProvider = AsyncNotifierProvider<StaffListNotifier, List<Map<String, dynamic>>>(StaffListNotifier.new);

// ─── Staff Stats Provider ────────────────────────────────────────────────────
final staffStatsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final response = await supabase.from('staff').select('status');
  final list = List<Map<String, dynamic>>.from(response);
  final total = list.length;
  final active = list.where((s) => s['status'] == 'active').length;
  return {
    'total': total,
    'active': active,
    'inactive': total - active,
  };
});

// ─── Staff Work History Provider ──────────────────────────────────────────────
final staffWorkHistoryProvider = FutureProvider.autoDispose.family<
    List<Map<String, dynamic>>, String>((ref, staffId) async {
  final supabase = ref.watch(supabaseClientProvider);
  
  // 1. Fetch task IDs assigned to the staff from task_staff
  final assignedRes = await supabase
      .from('task_staff')
      .select('task_id')
      .eq('staff_id', staffId);
      
  final assignedTaskIds = List<String>.from(
    (assignedRes as List).map((e) => e['task_id'] as String),
  );

  // 2. Query tasks with OR condition
  var query = supabase
      .from('tasks')
      .select('*, customers(name)');

  if (assignedTaskIds.isNotEmpty) {
    final filterString = 'id.in.(${assignedTaskIds.join(",")}),started_by.eq.$staffId,completed_by.eq.$staffId';
    query = query.or(filterString);
  } else {
    query = query.or('started_by.eq.$staffId,completed_by.eq.$staffId');
  }

  final response = await query.order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(response);
});

// ─── Staff List Screen ────────────────────────────────────────────────────────
class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val, StaffFilter filter) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      ref.read(staffFilterProvider.notifier).updateFilter(
        filter.copyWith(query: val),
      );
    });
  }

  String _formatRoleLabel(String? role) {
    switch (role) {
      case 'admin': return 'Admin';
      case 'office_staff': return 'Office Staff';
      case 'installer': return 'Structure Installer';
      case 'wireman': return 'Wireman / Electrical Installer';
      case 'supervisor': return 'Supervisor';
      case 'delivery_staff': return 'Delivery Staff';
      default: return role ?? 'Staff';
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    final statsAsync = ref.watch(staffStatsProvider);
    final filter = ref.watch(staffFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.blue),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddStaffScreen()));
              ref.invalidate(staffListProvider);
              ref.invalidate(staffStatsProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Stats Counter Header
          statsAsync.when(
            data: (stats) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn('TOTAL STAFF', stats['total'] ?? 0, Colors.black87),
                  _buildStatColumn('ACTIVE', stats['active'] ?? 0, Colors.green),
                  _buildStatColumn('INACTIVE', stats['inactive'] ?? 0, Colors.red),
                ],
              ),
            ),
            loading: () => const SizedBox(height: 50, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SizedBox.shrink(),
          ),
          
          // 2. Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '🔍 Search staff...',
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(staffFilterProvider.notifier).updateFilter(filter.copyWith(query: ''));
                        },
                      )
                    : null,
              ),
              onChanged: (val) => _onSearchChanged(val, filter),
            ),
          ),

          // 3. Filter Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: filter.role,
                    decoration: const InputDecoration(labelText: 'Role', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All Roles')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'office_staff', child: Text('Office Staff')),
                      DropdownMenuItem(value: 'installer', child: Text('Structure Installer')),
                      DropdownMenuItem(value: 'wireman', child: Text('Wireman / Electrical Installer')),
                      DropdownMenuItem(value: 'delivery_staff', child: Text('Delivery Staff')),
                      DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                    ],
                    onChanged: (val) {
                      ref.read(staffFilterProvider.notifier).updateFilter(filter.copyWith(role: val ?? 'All'));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: filter.status,
                    decoration: const InputDecoration(labelText: 'Status', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (val) {
                      ref.read(staffFilterProvider.notifier).updateFilter(filter.copyWith(status: val ?? 'All'));
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4. Staff List
          Expanded(
            child: staffAsync.when(
              data: (staffList) {
                if (staffList.isEmpty) return const Center(child: Text('No staff found.'));
                
                return ListView.builder(
                  itemCount: staffList.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemBuilder: (context, index) {
                    final staff = staffList[index];
                    
                    // Count assigned vs completed tasks
                    int assignedCount = 0;
                    int completedCount = 0;
                    final taskStaff = staff['task_staff'] as List?;
                    if (taskStaff != null) {
                      for (var ts in taskStaff) {
                        final task = ts['tasks'];
                        if (task != null) {
                          assignedCount++;
                          if (task['status'] == 'completed') {
                            completedCount++;
                          }
                        }
                      }
                    }

                    final isActive = staff['status'] == 'active';
                    final roleLabel = _formatRoleLabel(staff['role']);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: (staff['profile_photo_url'] != null && staff['profile_photo_url'].toString().isNotEmpty)
                              ? NetworkImage(staff['profile_photo_url'])
                              : null,
                          backgroundColor: (staff['profile_photo_url'] != null && staff['profile_photo_url'].toString().isNotEmpty)
                              ? Colors.transparent
                              : (isActive ? Colors.green.shade100 : Colors.grey.shade300),
                          child: (staff['profile_photo_url'] != null && staff['profile_photo_url'].toString().isNotEmpty)
                              ? null
                              : Icon(Icons.person, color: isActive ? Colors.green : Colors.grey),
                        ),
                        title: Text(staff['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$roleLabel • ${isActive ? "🟢 Active" : "🔴 Inactive"}', style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('Tasks: $assignedCount   Completed: $completedCount', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => StaffDetailsScreen(staff: staff),
                          )).then((_) {
                            ref.invalidate(staffListProvider);
                            ref.invalidate(staffStatsProvider);
                          });
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, int count, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// ─── Staff Details Screen ─────────────────────────────────────────────────────
class StaffDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> staff;
  const StaffDetailsScreen({super.key, required this.staff});

  @override
  ConsumerState<StaffDetailsScreen> createState() => _StaffDetailsScreenState();
}

class _StaffDetailsScreenState extends ConsumerState<StaffDetailsScreen> {
  late Map<String, dynamic> _currentStaff;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _currentStaff = widget.staff;
  }

  Future<void> _updateProfilePicture(ImageSource source) async {
    final picker = ImagePicker();
    try {
      XFile? image;
      Uint8List? bytes;

      try {
        image = await picker.pickImage(
          source: source,
          imageQuality: 50,
          maxWidth: 400,
          maxHeight: 400,
        );
        if (image == null) return;
        bytes = await image.readAsBytes();
      } catch (e) {
        if (e.toString().contains('MissingPluginException') && source == ImageSource.gallery) {
          final result = await FilePicker.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          );
          if (result == null || result.files.isEmpty) return;
          final file = result.files.first;
          bytes = file.bytes;
          final path = file.path;
          if (bytes == null && path != null && !kIsWeb) {
            bytes = await io.File(path).readAsBytes();
          }
          if (bytes == null) throw Exception('Could not read file bytes');
          image = XFile.fromData(bytes, name: file.name);
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Text('Uploading profile picture...'),
          ],
        )),
      );

      final supabase = ref.read(supabaseClientProvider);
      final staffId = _currentStaff['id'];
      
      final fileExtension = image.path.isNotEmpty ? image.path.split('.').last : 'png';
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final path = '$staffId/$fileName';

      await supabase.storage.from('avatars').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);

      await supabase.from('staff').update({
        'profile_photo_url': publicUrl,
      }).eq('id', staffId);

      final oldUrl = _currentStaff['profile_photo_url'] as String?;
      if (oldUrl != null && oldUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(oldUrl);
          final pathSegments = uri.pathSegments;
          final avatarsIdx = pathSegments.indexOf('avatars');
          if (avatarsIdx >= 0 && pathSegments.length > avatarsIdx + 2) {
            final oldPath = pathSegments.sublist(avatarsIdx + 1).join('/');
            await supabase.storage.from('avatars').remove([oldPath]);
          }
        } catch (_) {}
      }

      setState(() {
        _currentStaff = {
          ..._currentStaff,
          'profile_photo_url': publicUrl,
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _removeProfilePicture() async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Text('Removing profile picture...'),
          ],
        )),
      );

      final supabase = ref.read(supabaseClientProvider);
      final staffId = _currentStaff['id'];
      final oldUrl = _currentStaff['profile_photo_url'] as String?;

      await supabase.from('staff').update({
        'profile_photo_url': null,
      }).eq('id', staffId);

      if (oldUrl != null && oldUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(oldUrl);
          final pathSegments = uri.pathSegments;
          final avatarsIdx = pathSegments.indexOf('avatars');
          if (avatarsIdx >= 0 && pathSegments.length > avatarsIdx + 2) {
            final oldPath = pathSegments.sublist(avatarsIdx + 1).join('/');
            await supabase.storage.from('avatars').remove([oldPath]);
          }
        } catch (_) {}
      }

      setState(() {
        _currentStaff = {
          ..._currentStaff,
          'profile_photo_url': null,
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remove failed: $e')),
        );
      }
    }
  }

  void _showPhotoOptions() {
    final loggedInUserId = ref.read(currentUserProvider)?.id;
    final loggedInUserRole = ref.read(userRoleProvider).value;
    final bool canEdit = (loggedInUserId == _currentStaff['id']) || (loggedInUserRole == 'admin');
    if (!canEdit) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        final hasPhoto = _currentStaff['profile_photo_url'] != null && _currentStaff['profile_photo_url'].toString().isNotEmpty;
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Photo from Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _updateProfilePicture(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose Photo from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _updateProfilePicture(ImageSource.gallery);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _removeProfilePicture();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? Colors.blue : Colors.black87,
      ),
      selected: selected,
      onSelected: (val) {
        if (val) {
          setState(() => _statusFilter = value);
        }
      },
    );
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) => _EditStaffDialog(staff: _currentStaff),
    ).then((updated) {
      if (updated != null && updated is Map<String, dynamic>) {
        setState(() {
          _currentStaff = {
            ..._currentStaff,
            ...updated,
          };
        });
      }
    });
  }

  String _formatRoleLabel(String? role) {
    switch (role) {
      case 'admin': return 'Admin';
      case 'office_staff': return 'Office Staff';
      case 'installer': return 'Structure Installer';
      case 'wireman': return 'Wireman / Electrical Installer';
      case 'supervisor': return 'Supervisor';
      case 'delivery_staff': return 'Delivery Staff';
      default: return role ?? 'Staff';
    }
  }

  void _showResetPasswordDialog() {
    final passwordController = TextEditingController();
    bool obscure = true;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Reset Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set new password for ${_currentStaff['name']}:',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      hintText: 'Minimum 6 characters',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    final newPass = passwordController.text.trim();
                    if (newPass.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password must be at least 6 characters')),
                      );
                      return;
                    }
                    setDialogState(() => isSaving = true);
                    try {
                      final supabase = ref.read(supabaseClientProvider);
                      await supabase.rpc('admin_reset_staff_password', params: {
                        'target_user_id': _currentStaff['id'],
                        'new_password': newPass,
                      });
                      if (context.mounted) {
                        Navigator.pop(dialogCtx);
                        _showPasswordResetSuccessDialog(newPass);
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error resetting password: $e')),
                        );
                      }
                    }
                  },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('UPDATE PASSWORD'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPasswordResetSuccessDialog(String newPassword) {
    final staffName = _currentStaff['name'] ?? 'Staff';
    final username = _currentStaff['mobile'] ?? _currentStaff['email'] ?? '';
    final credText = "Siya Solar Staff Credentials:\nUser: $staffName\nUsername/Mobile: $username\nPassword: $newPassword";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Password Updated!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Password for $staffName was successfully updated.', style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Username: $username', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('New Password: $newPassword', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () async {
              try {
                await SharePlus.instance.share(ShareParams(text: credText));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: credText));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied credentials to clipboard!')));
                }
              }
            },
            icon: const Icon(Icons.share, size: 16),
            label: const Text('SHARE CREDENTIALS'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(staffWorkHistoryProvider(_currentStaff['id']));
    final role = _formatRoleLabel(_currentStaff['role']);
    final isActive = _currentStaff['status'] == 'active';

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentStaff['name'] ?? 'Staff Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.blue),
            tooltip: 'Share',
            onPressed: () async {
              final shareText = "Staff: ${_currentStaff['name'] ?? 'Unknown'}\n"
                  "Role: $role\n"
                  "Status: ${isActive ? 'Active' : 'Inactive'}";
              try {
                await SharePlus.instance.share(ShareParams(text: shareText));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: shareText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share sheet not supported. Copied to clipboard!')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _showPhotoOptions,
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 32,
                                  backgroundImage: (_currentStaff['profile_photo_url'] != null && _currentStaff['profile_photo_url'].toString().isNotEmpty)
                                      ? NetworkImage(_currentStaff['profile_photo_url'])
                                      : null,
                                  backgroundColor: (_currentStaff['profile_photo_url'] != null && _currentStaff['profile_photo_url'].toString().isNotEmpty)
                                      ? Colors.transparent
                                      : (isActive ? Colors.green.shade100 : Colors.grey.shade300),
                                  child: (_currentStaff['profile_photo_url'] != null && _currentStaff['profile_photo_url'].toString().isNotEmpty)
                                      ? null
                                      : Text(
                                          (_currentStaff['name'] as String? ?? 'Unknown').isNotEmpty
                                              ? (_currentStaff['name'] as String)[0].toUpperCase()
                                              : 'S',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: isActive ? Colors.green.shade900 : Colors.grey.shade700,
                                          ),
                                        ),
                                ),
                                if (ref.read(currentUserProvider)?.id == _currentStaff['id'] || ref.read(userRoleProvider).value == 'admin')
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentStaff['name'] ?? 'Unknown',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(role, style: TextStyle(color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                            onPressed: _showEditDialog,
                          ),
                        ],
                      ),
                      const Divider(),
                      _buildInfoRow('Role:', role),
                      _buildInfoRow('Mobile:', _currentStaff['mobile'] ?? 'N/A'),
                      _buildInfoRow('Status:', isActive ? 'Active' : 'Inactive', color: isActive ? Colors.green : Colors.red),
                      _buildInfoRow('App Version:', '${_currentStaff['app_version'] ?? "N/A"} (${_currentStaff['build_number'] ?? "N/A"})'),
                      _buildInfoRow('Last Active:', _currentStaff['last_active_at'] != null ? AppDateUtils.formatDateTime(_currentStaff['last_active_at']) : 'N/A'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Login Credentials Card (Admin View)
              Card(
                color: Colors.blue.shade50,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.blue.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.vpn_key, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('LOGIN CREDENTIALS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Username / Mobile: ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                          Expanded(
                            child: SelectableText(
                              _currentStaff['mobile'] ?? _currentStaff['email'] ?? 'N/A',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18, color: Colors.blue),
                            tooltip: 'Copy Username',
                            onPressed: () {
                              final text = _currentStaff['mobile'] ?? _currentStaff['email'] ?? '';
                              Clipboard.setData(ClipboardData(text: text));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username copied to clipboard!')));
                            },
                          ),
                        ],
                      ),
                      if (_currentStaff['email'] != null) ...[
                        Row(
                          children: [
                            const Text('Login Email: ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                            Expanded(
                              child: SelectableText(
                                _currentStaff['email'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (ref.read(userRoleProvider).value == 'admin') ...[
                        const Divider(),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showResetPasswordDialog,
                            icon: const Icon(Icons.lock_reset, size: 18),
                            label: const Text('RESET / CHANGE STAFF PASSWORD'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // KPI Counts (Today's Assigned, Completed, Pending, Assigned Sites)
              historyAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error computing stats: $e')),
                data: (tasks) {
                  final now = DateTime.now();
                  final todayStart = DateTime(now.year, now.month, now.day);

                  final todayAssigned = tasks.where((t) {
                    final createdAt = DateTime.tryParse(t['created_at'] ?? '');
                    return createdAt != null && createdAt.isAfter(todayStart);
                  }).length;

                  final todayCompleted = tasks.where((t) {
                    if (t['status'] != 'completed') return false;
                    final completedAt = DateTime.tryParse(t['completed_at'] ?? '');
                    return completedAt != null && completedAt.isAfter(todayStart);
                  }).length;

                  final pendingTasks = tasks.where((t) => t['status'] != 'completed').length;
                  final assignedSites = tasks.map((t) => t['customer_id']).where((id) => id != null).toSet().length;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'TODAY',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      _buildKpiRow('Assigned Tasks', todayAssigned),
                      _buildKpiRow('Completed', todayCompleted, color: Colors.green),
                      _buildKpiRow('Pending', pendingTasks, color: Colors.orange),
                      const SizedBox(height: 16),
                      const Text(
                        'CUSTOMERS / SITES',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      _buildKpiRow('Assigned Sites', assignedSites, color: Colors.purple),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Action Buttons: VIEW TASKS, VIEW SITES, ACTIVITY
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => StaffTasksScreen(staffId: _currentStaff['id'], staffName: _currentStaff['name']),
                        ));
                      },
                      icon: const Icon(Icons.list_alt_outlined, size: 16),
                      label: const Text('VIEW TASKS', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => StaffSitesScreen(staffId: _currentStaff['id'], staffName: _currentStaff['name']),
                        ));
                      },
                      icon: const Icon(Icons.location_city_outlined, size: 16),
                      label: const Text('VIEW SITES', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => StaffActivityFeedScreen(staffId: _currentStaff['id'], staffName: _currentStaff['name']),
                  ));
                },
                icon: const Icon(Icons.history_outlined, size: 16),
                label: const Text('ACTIVITY FEED'),
              ),
              const SizedBox(height: 24),

              // Work History / Tasks header and List
              const Text(
                'WORK HISTORY / TASKS',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    _buildFilterChip('All', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', 'pending'),
                    const SizedBox(width: 8),
                    _buildFilterChip('In Progress', 'in_progress'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Completed', 'completed'),
                  ],
                ),
              ),

              // Tasks List
              historyAsync.when(
                loading: () => const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Center(child: Text('Error loading history: $e')),
                data: (tasks) {
                  final filteredTasks = _statusFilter == 'all'
                      ? tasks
                      : tasks.where((t) => (t['status'] as String? ?? 'pending').toLowerCase() == _statusFilter).toList();

                  if (filteredTasks.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            _statusFilter == 'all'
                                ? 'No task history found for this staff member.'
                                : 'No task history matches the selected filter.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredTasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final t = filteredTasks[i];
                      final tStatus = t['status'] as String? ?? 'pending';
                      final custName = (t['customers'] as Map?)?['name'] as String? ?? 'No Customer';

                      Color statusColor = Colors.orange;
                      if (tStatus == 'completed') statusColor = Colors.green;
                      if (tStatus == 'in_progress') statusColor = Colors.blue;

                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => TaskDetailsScreen(task: t),
                            )).then((_) => ref.invalidate(staffWorkHistoryProvider(_currentStaff['id'])));
                          },
                          title: Text(t['name'] ?? 'Task', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Customer: $custName', style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 4),
                              if (t['started_at'] != null)
                                Text('Started: ${AppDateUtils.formatDateTime(t['started_at'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              if (t['completed_at'] != null)
                                Text('Completed: ${AppDateUtils.formatDateTime(t['completed_at'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tStatus.toUpperCase(),
                              style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color ?? Colors.black87, fontWeight: color != null ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow(String title, int count, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          Text(
            count.toString(),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? Colors.black87),
          ),
        ],
      ),
    );
  }
}

// ─── Staff Tasks Screen ────────────────────────────────────────────────────────
final staffTasksProvider = FutureProvider.autoDispose.family<
    List<Map<String, dynamic>>, ({String staffId, String query})>((ref, arg) async {
  final supabase = ref.watch(supabaseClientProvider);
  
  // 1. Fetch task IDs assigned to the staff from task_staff
  final assignedRes = await supabase
      .from('task_staff')
      .select('task_id')
      .eq('staff_id', arg.staffId);
      
  final taskIds = List<String>.from(
    (assignedRes as List).map((e) => e['task_id'] as String),
  );
  if (taskIds.isEmpty) return [];

  // 2. Query tasks with filters
  var queryBuilder = supabase
      .from('tasks')
      .select('*, customers(name, customer_id)')
      .inFilter('id', taskIds);

  if (arg.query.isNotEmpty) {
    queryBuilder = queryBuilder.ilike('name', '%${arg.query}%');
  }

  final response = await queryBuilder.order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(response);
});

class StaffTasksScreen extends ConsumerStatefulWidget {
  final String staffId;
  final String staffName;
  const StaffTasksScreen({super.key, required this.staffId, required this.staffName});

  @override
  ConsumerState<StaffTasksScreen> createState() => _StaffTasksScreenState();
}

class _StaffTasksScreenState extends ConsumerState<StaffTasksScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      setState(() => _searchQuery = val);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(staffTasksProvider((staffId: widget.staffId, query: _searchQuery)));

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.staffName}\'s Tasks'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '🔍 Search tasks by name...',
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading tasks: $e')),
              data: (tasks) {
                if (tasks.isEmpty) {
                  return const Center(child: Text('No tasks found.', style: TextStyle(color: Colors.grey)));
                }

                return ListView.separated(
                  itemCount: tasks.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final t = tasks[idx];
                    final tStatus = t['status'] as String? ?? 'pending';
                    final custName = (t['customers'] as Map?)?['name'] as String? ?? 'No Customer';

                    Color statusColor = Colors.orange;
                    if (tStatus == 'completed') statusColor = Colors.green;
                    if (tStatus == 'in_progress') statusColor = Colors.blue;

                    return Card(
                      child: ListTile(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => TaskDetailsScreen(task: t),
                          )).then((_) => ref.invalidate(staffTasksProvider((staffId: widget.staffId, query: _searchQuery))));
                        },
                        title: Text(t['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Customer: $custName'),
                            if (t['created_at'] != null)
                              Text('Created: ${AppDateUtils.formatDateTime(t['created_at'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text(tStatus.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Staff Sites Screen ────────────────────────────────────────────────────────
final staffSitesProvider = FutureProvider.autoDispose.family<
    List<Map<String, dynamic>>, String>((ref, staffId) async {
  final supabase = ref.watch(supabaseClientProvider);
  
  // 1. Fetch task IDs assigned to the staff from task_staff
  final assignedRes = await supabase
      .from('task_staff')
      .select('task_id')
      .eq('staff_id', staffId);
      
  final taskIds = List<String>.from(
    (assignedRes as List).map((e) => e['task_id'] as String),
  );
  if (taskIds.isEmpty) return [];

  // 2. Fetch unique customer IDs
  final tasksRes = await supabase.from('tasks').select('customer_id').inFilter('id', taskIds);
  final custIds = (tasksRes as List)
      .map((e) => e['customer_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();
  if (custIds.isEmpty) return [];

  // 3. Query customers details
  final response = await supabase.from('customers').select('*').inFilter('id', custIds).order('name');
  return List<Map<String, dynamic>>.from(response);
});

class StaffSitesScreen extends ConsumerWidget {
  final String staffId;
  final String staffName;
  const StaffSitesScreen({super.key, required this.staffId, required this.staffName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(staffSitesProvider(staffId));

    return Scaffold(
      appBar: AppBar(
        title: Text('$staffName\'s Sites'),
      ),
      body: sitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading sites: $e')),
        data: (sites) {
          if (sites.isEmpty) {
            return const Center(child: Text('No assigned sites found.', style: TextStyle(color: Colors.grey)));
          }

          return ListView.separated(
            itemCount: sites.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final c = sites[idx];
              return Card(
                child: ListTile(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: c)));
                  },
                  title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ${c['customer_id'] ?? ""} • Village: ${c['village'] ?? "N/A"}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Staff Activity Feed Screen ───────────────────────────────────────────────
class StaffActivityFeedScreen extends ConsumerStatefulWidget {
  final String staffId;
  final String staffName;
  const StaffActivityFeedScreen({super.key, required this.staffId, required this.staffName});

  @override
  ConsumerState<StaffActivityFeedScreen> createState() => _StaffActivityFeedScreenState();
}

class _StaffActivityFeedScreenState extends ConsumerState<StaffActivityFeedScreen> {
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _activities = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetchPage(0);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int page) async {
    if (page == 0) {
      setState(() {
        _isLoading = true;
        _activities.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final supabase = ref.read(supabaseClientProvider);
      final response = await supabase
          .from('activity_log')
          .select('*, customers(name)')
          .eq('performed_by', widget.staffId)
          .order('created_at', ascending: false)
          .range(page * _pageSize, (page + 1) * _pageSize - 1);

      final list = List<Map<String, dynamic>>.from(response);
      if (mounted) {
        setState(() {
          _activities.addAll(list);
          _page = page;
          _hasMore = list.length == _pageSize;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading activity: $e')));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    await _fetchPage(_page + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.staffName}\'s Activity'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
              ? const Center(child: Text('No activity logs found for this staff.', style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: () => _fetchPage(0),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _activities.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _activities.length) {
                        return _hasMore
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : const SizedBox.shrink();
                      }

                      final log = _activities[index];
                      final custName = (log['customers'] as Map?)?['name'] as String? ?? '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.history_outlined, size: 18, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      log['description'] ?? 'Activity',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              if (custName.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Site: $custName', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                AppDateUtils.formatDateTime(log['created_at']),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── Edit Staff Dialog ────────────────────────────────────────────────────────
class _EditStaffDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> staff;
  const _EditStaffDialog({required this.staff});

  @override
  ConsumerState<_EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends ConsumerState<_EditStaffDialog> {
  late String _role;
  late String _status;
  late TextEditingController _nameController;
  late TextEditingController _mobileController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _role = widget.staff['role'];
    _status = widget.staff['status'];
    _nameController = TextEditingController(text: widget.staff['name']);
    _mobileController = TextEditingController(text: widget.staff['mobile']);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.from('staff').update({
        'name': _nameController.text.trim(),
        'mobile': _mobileController.text.trim(),
        'role': _role,
        'status': _status,
      }).eq('id', widget.staff['id']);
      
      if (mounted) {
        Navigator.pop(context, {
          'name': _nameController.text.trim(),
          'mobile': _mobileController.text.trim(),
          'role': _role,
          'status': _status,
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.staff['name']}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobileController,
              decoration: const InputDecoration(labelText: 'Mobile Number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'office_staff', child: Text('Office Staff')),
                DropdownMenuItem(value: 'installer', child: Text('Structure Installer')),
                DropdownMenuItem(value: 'wireman', child: Text('Wireman / Electrical Installer')),
                DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                DropdownMenuItem(value: 'delivery_staff', child: Text('Delivery Staff')),
              ],
              onChanged: (val) => setState(() => _role = val!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (val) => setState(() => _status = val!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('SAVE'),
        ),
      ],
    );
  }
}
