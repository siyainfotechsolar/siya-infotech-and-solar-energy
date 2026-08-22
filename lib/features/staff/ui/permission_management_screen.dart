import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/utils/audit_logger.dart';
import '../../auth/providers/auth_provider.dart';

class PermissionManagementScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> staffMember;

  const PermissionManagementScreen({
    super.key,
    required this.staffMember,
  });

  @override
  ConsumerState<PermissionManagementScreen> createState() => _PermissionManagementScreenState();
}

class _PermissionManagementScreenState extends ConsumerState<PermissionManagementScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  late StaffCategory _selectedCategory;
  late DataAccessLevel _selectedAccessLevel;
  late Map<String, ModulePermissionState> _moduleStates;

  @override
  void initState() {
    super.initState();
    _initPermissions();
  }

  Future<void> _initPermissions() async {
    setState(() => _isLoading = true);
    final staffId = widget.staffMember['id'] as String;
    final currentRole = widget.staffMember['role'] as String?;
    final currentCategory = widget.staffMember['category'] as String?;
    
    _selectedCategory = StaffCategory.fromRole(currentRole, currentCategory);
    
    final service = ref.read(permissionServiceProvider);
    final existingPerms = await service.fetchUserPermissions(staffId);
    
    _selectedAccessLevel = existingPerms.dataAccessLevel;
    _moduleStates = Map<String, ModulePermissionState>.from(existingPerms.modules);

    // If permissions were uninitialized or empty, populate category defaults
    if (_moduleStates.values.every((m) => !m.enabled)) {
      final defaultPerms = StaffPermissions.getDefault(staffId, _selectedCategory);
      _selectedAccessLevel = defaultPerms.dataAccessLevel;
      _moduleStates = Map<String, ModulePermissionState>.from(defaultPerms.modules);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _applyCategoryDefaults(StaffCategory newCategory) {
    final staffId = widget.staffMember['id'] as String;
    final defaults = StaffPermissions.getDefault(staffId, newCategory);
    setState(() {
      _selectedCategory = newCategory;
      _selectedAccessLevel = defaults.dataAccessLevel;
      _moduleStates = Map<String, ModulePermissionState>.from(defaults.modules);
    });
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);
    try {
      final currentUser = ref.read(currentUserProvider);
      final staffId = widget.staffMember['id'] as String;
      final service = ref.read(permissionServiceProvider);

      final updatedPerms = StaffPermissions(
        staffId: staffId,
        category: _selectedCategory,
        dataAccessLevel: _selectedAccessLevel,
        modules: _moduleStates,
      );

      await service.saveStaffPermissions(updatedPerms, currentUser?.id ?? '');

      if (currentUser != null) {
        final supabase = ref.read(supabaseClientProvider);
        await AuditLogger.log(
          supabase: supabase,
          userId: currentUser.id,
          action: 'PERMISSIONS_UPDATED',
          module: 'staff',
          entityId: staffId,
          details: {
            'target_staff_name': widget.staffMember['name'],
            'category': _selectedCategory.displayName,
            'access_level': _selectedAccessLevel.toDbString(),
          },
        );
      }

      // Invalidate current permissions provider so system updates instantly
      ref.invalidate(currentUserPermissionsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permissions saved for ${widget.staffMember['name']}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save permissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.staffMember['name'] ?? 'Staff Member';
    final mobile = widget.staffMember['mobile'] ?? 'N/A';
    final status = widget.staffMember['status'] ?? 'active';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access & Permissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset to Category Defaults',
            onPressed: () => _applyCategoryDefaults(_selectedCategory),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Staff Header Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'S',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Mobile: $mobile',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: status == 'active' ? Colors.green.shade100 : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: status == 'active' ? Colors.green.shade900 : Colors.red.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 2. Staff Category Dropdown
                  const Text('STAFF CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<StaffCategory>(
                    initialValue: _selectedCategory,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: StaffCategory.all.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null && val != _selectedCategory) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Apply Category Defaults?'),
                            content: Text('Changing category to ${val.displayName} will update default permissions. Continue?'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  setState(() => _selectedCategory = val);
                                },
                                child: const Text('KEEP CUSTOM PERMISSIONS'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _applyCategoryDefaults(val);
                                },
                                child: const Text('APPLY DEFAULTS'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // 3. Data Access Level Dropdown
                  const Text('DATA ACCESS LEVEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<DataAccessLevel>(
                    initialValue: _selectedAccessLevel,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: DataAccessLevel.values.map((lvl) {
                      return DropdownMenuItem(
                        value: lvl,
                        child: Text(lvl.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedAccessLevel = val);
                      }
                    },
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // 4. Module Access Matrix
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'MODULE ACCESS & PERMISSIONS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Reset Defaults'),
                        onPressed: () => _applyCategoryDefaults(_selectedCategory),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  ...AppModule.all.map((modKey) {
                    final modState = _moduleStates[modKey] ?? ModulePermissionState.disabled();
                    final label = AppModule.getLabel(modKey);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: modState.enabled ? Theme.of(context).primaryColor.withValues(alpha: 0.3) : Colors.grey.shade300,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: modState.enabled ? Colors.black87 : Colors.grey,
                                  ),
                                ),
                                Switch(
                                  value: modState.enabled,
                                  activeThumbColor: Theme.of(context).primaryColor,
                                  onChanged: (val) {
                                    setState(() {
                                      _moduleStates[modKey] = modState.copyWith(enabled: val);
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (modState.enabled) ...[
                              const Divider(height: 16),
                              const Text(
                                'Action Permissions:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: PermissionAction.all.map((action) {
                                  final isActionOn = modState.can(action);
                                  return FilterChip(
                                    label: Text(action.toUpperCase(), style: const TextStyle(fontSize: 11)),
                                    selected: isActionOn,
                                    selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                                    checkmarkColor: Theme.of(context).primaryColor,
                                    onSelected: (selected) {
                                      final newActions = Map<String, bool>.from(modState.actions);
                                      newActions[action] = selected;
                                      setState(() {
                                        _moduleStates[modKey] = modState.copyWith(actions: newActions);
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 24),

                  // 5. Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _savePermissions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(
                        _isSaving ? 'SAVING PERMISSIONS...' : 'SAVE ACCESS & PERMISSIONS',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}
