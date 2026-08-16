import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../../auth/providers/auth_provider.dart';
import 'widgets/customer_search_field.dart';
import 'widgets/task_name_search_field.dart';
import 'task_details_screen.dart';
import '../providers/task_provider.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/services/global_loading_service.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/notifications/notification_state.dart';

class AddTaskScreen extends ConsumerStatefulWidget {
  final String? initialCustomerId;
  const AddTaskScreen({super.key, this.initialCustomerId});

  @override
  ConsumerState<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends ConsumerState<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  
  String? _taskName;
  String? _selectedCustomerId;
  String _priority = 'normal';
  
  List<Map<String, dynamic>> _staff = [];
  final List<String> _selectedStaffIds = [];
  
  bool _isLoading = true;
  bool _isSaving = false;
  final List<Map<String, dynamic>> _attachments = [];

  Future<void> _addPdfAttachment() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      setState(() {
        _attachments.add({
          'name': file.name,
          'bytes': file.bytes,
          'size': file.size,
          'type': 'pdf',
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick PDF: $e')),
        );
      }
    }
  }

  Future<void> _addPhotoAttachment() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      setState(() {
        _attachments.add({
          'name': file.name,
          'bytes': file.bytes,
          'size': file.size,
          'type': 'photo',
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick photo: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = widget.initialCustomerId;
    _fetchData();
  }
  
  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      
      final staffRes = await supabase.from('staff').select('id, name, role').eq('status', 'active').order('name');
      
      if (mounted) {
        setState(() {
          _staff = List<Map<String, dynamic>>.from(staffRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatRoleTag(String? role) {
    switch (role) {
      case 'admin': return 'Admin';
      case 'office_staff': return 'Office Staff';
      case 'installer': return 'Structure Installer';
      case 'wireman': return 'Wireman';
      case 'supervisor': return 'Supervisor';
      case 'delivery_staff': return 'Delivery Staff';
      default: return role ?? 'Staff';
    }
  }

  bool _isRecommendedStaff(String? taskName, String? role) {
    if (taskName == null || taskName.trim().isEmpty) return false;
    final nameLower = taskName.toLowerCase();
    final roleLower = (role ?? '').toLowerCase();

    if (nameLower.contains('structure') || nameLower.contains('panel')) {
      return roleLower == 'installer';
    }
    if (nameLower.contains('wiring') || nameLower.contains('dc') || nameLower.contains('ac') || 
        nameLower.contains('inverter') || nameLower.contains('earthing') || nameLower.contains('meter') || nameLower.contains('electrical')) {
      return roleLower == 'wireman';
    }
    if (nameLower.contains('delivery')) {
      return roleLower == 'delivery_staff';
    }
    return false;
  }

  Future<void> _saveTask() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    if (_taskName == null || _taskName!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or enter a task name')));
      return;
    }
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_selectedStaffIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ASSIGN STAFF: Please select at least one staff member before creating this task.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);

    try {
      // 1. Check for ACTIVE duplicate task for the same customer
      final activeTasksRes = await supabase
          .from('tasks')
          .select('*, customers(name, customer_id)')
          .eq('customer_id', _selectedCustomerId!)
          .ilike('name', _taskName!.trim())
          .inFilter('status', ['pending', 'in_progress', 'not_completed']);

      final activeList = List<Map<String, dynamic>>.from(activeTasksRes);

      if (activeList.isNotEmpty) {
        setState(() => _isSaving = false);
        if (!mounted) return;

        final existingTask = activeList.first;
        final statusLabel = (existingTask['status'] as String? ?? 'active').replaceAll('_', ' ').toUpperCase();

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('TASK ALREADY EXISTS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'This task ("${_taskName!.trim()}") has already been created for this customer and is currently in status "$statusLabel".\n\nTo prevent duplicate tasks, please view or update the existing task.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => TaskDetailsScreen(task: existingTask)),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: const Text('VIEW EXISTING TASK'),
              ),
            ],
          ),
        );
        return;
      }

      // 2. Check if task was PREVIOUSLY COMPLETED (Repeat task confirmation)
      final completedTasksRes = await supabase
          .from('tasks')
          .select('id, created_at, completed_at')
          .eq('customer_id', _selectedCustomerId!)
          .ilike('name', _taskName!.trim())
          .eq('status', 'completed');

      final completedList = List<Map<String, dynamic>>.from(completedTasksRes);

      String? repeatReason;
      if (completedList.isNotEmpty) {
        setState(() => _isSaving = false);
        if (!mounted) return;

        final reasonController = TextEditingController();
        final formKey = GlobalKey<FormState>();

        final confirmRepeat = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('TASK PREVIOUSLY COMPLETED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This task was previously completed for this customer.'),
                  const SizedBox(height: 12),
                  const Text('Please provide a reason to create a repeat task *:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: reasonController,
                    decoration: const InputDecoration(labelText: 'Reason for Repeat Task', border: OutlineInputBorder()),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Reason is required' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    repeatReason = reasonController.text.trim();
                    Navigator.pop(dialogCtx, true);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: const Text('CREATE REPEAT TASK'),
              ),
            ],
          ),
        );

        if (confirmRepeat != true || repeatReason == null) {
          return;
        }

        setState(() => _isSaving = true);
      }

      // 3. Create single Task record
      await ref.read(globalLoadingProvider.notifier).runWithLoading(
        () async {
          if (_taskName != null) {
            try {
              await supabase.from('task_types').insert({'name': _taskName!.trim()});
            } catch (_) {}
          }

          final taskResp = await supabase.from('tasks').insert({
            'name': _taskName!.trim(),
            'customer_id': _selectedCustomerId,
            'description': repeatReason != null 
                ? '${_descController.text.trim()}\n[Repeat Task Reason: $repeatReason]' 
                : _descController.text.trim(),
            'priority': _priority,
            'created_by': user?.id,
          }).select('id').single();

          final taskId = taskResp['id'];

          // Create multi-staff mapping on the ONE task ID
          final staffMappings = _selectedStaffIds.map((staffId) => {
            'task_id': taskId,
            'staff_id': staffId,
          }).toList();

          await supabase.from('task_staff').insert(staffMappings);

          // Admin Name
          String adminName = 'Admin';
          if (user != null) {
            try {
              final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
              if (staffNameRes?['name'] != null) adminName = staffNameRes!['name'];
            } catch (_) {}
          }

          // Send FCM Notification ONCE to assigned staff
          final notificationRepo = ref.read(notificationRepositoryProvider);
          for (final staffId in _selectedStaffIds) {
            try {
              await notificationRepo.sendNotification(
                recipientUserId: staffId,
                notificationType: 'TASK_ASSIGNED',
                title: '🔔 New Task Assigned',
                message: 'You have been assigned to task:\n${_taskName!.trim()}\n\nAssigned by:\n$adminName',
                taskId: taskId,
              );
            } catch (err) {
              debugPrint('[AddTaskScreen] Failed to notify staff $staffId: $err');
            }
          }

          // Upload attachments if any
          for (final att in _attachments) {
            final bytes = att['bytes'] as Uint8List;
            final name = att['name'] as String;
            final size = att['size'] as int;
            final type = att['type'] as String;
            
            final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
            final filePath = '$taskId/attachment_${DateTime.now().millisecondsSinceEpoch}_$safeName';

            await supabase.storage.from('task_attachments').uploadBinary(
              filePath,
              bytes,
              fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
            );

            await supabase.from('task_attachments').insert({
              'task_id': taskId,
              'customer_id': _selectedCustomerId,
              'file_name': name,
              'file_path': filePath,
              'file_type': type,
              'file_size': size,
              'uploaded_by': user?.id,
            });
          }

          if (user != null) {
            try {
              await ActivityLogger.log(
                supabase: supabase,
                customerId: _selectedCustomerId,
                action: 'task_created',
                description: '$adminName added task ${_taskName!.trim()}',
                performedBy: user.id,
              );
            } catch (_) {}
          }

          ref.invalidate(taskListProvider);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Task assigned successfully!'), backgroundColor: Colors.green),
            );
            Navigator.pop(context);
          }
        },
        type: LoadingType.saveLoading,
        message: AppStrings.saveLoading,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving task: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create Task')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TaskNameSearchField(
                onTaskNameSelected: (name) => setState(() => _taskName = name),
              ),
              const SizedBox(height: 12),
              CustomerSearchField(
                initialCustomerId: _selectedCustomerId,
                onCustomerSelected: (id) => setState(() => _selectedCustomerId = id),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Priority'),
                initialValue: _priority,
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (val) => setState(() => _priority = val!),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Assign Staff *', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (_selectedStaffIds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Text('(Required)', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _staff.map((s) {
                  final id = s['id'] as String;
                  final roleTag = _formatRoleTag(s['role']);
                  final isSelected = _selectedStaffIds.contains(id);
                  final isRecommended = _isRecommendedStaff(_taskName, s['role']);

                  return FilterChip(
                    avatar: isRecommended ? const Icon(Icons.star, size: 14, color: Colors.amber) : null,
                    label: Text('${s['name']} ($roleTag)'),
                    selected: isSelected,
                    selectedColor: Colors.blue.shade100,
                    checkmarkColor: Colors.blue,
                    side: isRecommended ? const BorderSide(color: Colors.amber, width: 1.5) : null,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedStaffIds.add(id);
                        } else {
                          _selectedStaffIds.remove(id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              const Text('Attachments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _addPdfAttachment,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Add PDF'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _addPhotoAttachment,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Add Photo'),
                  ),
                ],
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    final att = _attachments[index];
                    final isPdf = att['type'] == 'pdf';
                    final sizeKb = ((att['size'] as int) / 1024).toStringAsFixed(1);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.image, color: Colors.blue),
                      title: Text(att['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('$sizeKb KB'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _attachments.removeAt(index);
                          });
                        },
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveTask,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: _isSaving ? Colors.grey : Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving 
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 12),
                        Text('Creating Task...'),
                      ],
                    )
                  : const Text('ASSIGN TASK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
