import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../../auth/providers/auth_provider.dart';
import 'widgets/customer_search_field.dart';
import 'widgets/task_name_search_field.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/services/global_loading_service.dart';
import '../../../core/localization/app_strings.dart';

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
      
      final staffRes = await supabase.from('staff').select('id, name, role').eq('status', 'active');
      
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

  Future<void> _saveTask() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_selectedStaffIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please assign at least one staff member')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      await ref.read(globalLoadingProvider.notifier).runWithLoading(
        () async {
          final supabase = ref.read(supabaseClientProvider);
          final user = ref.read(currentUserProvider);

          if (_taskName != null) {
            try {
              await supabase.from('task_types').insert({'name': _taskName!.trim()});
            } catch (_) {}
          }

          final taskResp = await supabase.from('tasks').insert({
            'name': _taskName!.trim(),
            'customer_id': _selectedCustomerId,
            'description': _descController.text.trim(),
            'priority': _priority,
            'created_by': user?.id,
          }).select('id').single();

          final taskId = taskResp['id'];

          // Create multi-staff mapping
          final staffMappings = _selectedStaffIds.map((staffId) => {
            'task_id': taskId,
            'staff_id': staffId,
          }).toList();

          await supabase.from('task_staff').insert(staffMappings);

          // Upload attachments
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
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: true,
              ),
            );

            await supabase.from('task_attachments').insert({
              'task_id': taskId,
              'file_name': name,
              'file_path': filePath,
              'file_type': type,
              'file_size': size,
              'uploaded_by': user?.id,
            });
          }

          if (user != null) {
            try {
              final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
              final staffName = staffNameRes?['name'] ?? 'Staff member';
              await ActivityLogger.log(
                supabase: supabase,
                customerId: _selectedCustomerId,
                action: 'task_created',
                description: '$staffName added task ${_taskName!.trim()}',
                performedBy: user.id,
              );
            } catch (_) {}
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task assigned successfully!')));
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
                value: _priority,
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (val) => setState(() => _priority = val!),
              ),
              const SizedBox(height: 24),
              const Text('Assign Staff *', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                children: _staff.map((s) {
                  final id = s['id'] as String;
                  final isSelected = _selectedStaffIds.contains(id);
                  return FilterChip(
                    label: Text(s['name']),
                    selected: isSelected,
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
                child: _isSaving 
                  ? const CircularProgressIndicator() 
                  : const Text('ASSIGN TASK'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
