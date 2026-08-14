import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../auth/providers/auth_provider.dart';
import 'task_file_viewer_screen.dart';
import '../providers/task_provider.dart';
import '../../../core/services/realtime_service.dart';
import '../../customers/ui/customer_details_screen.dart';
import '../../../core/utils/activity_logger.dart';

class TaskDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;
  
  const TaskDetailsScreen({super.key, required this.task});

  @override
  ConsumerState<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends ConsumerState<TaskDetailsScreen> {
  bool _isLoading = false;
  final _remarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(activeTaskIdProvider.notifier).update(widget.task['id']);
    });
  }

  @override
  void dispose() {
    ref.read(activeTaskIdProvider.notifier).update(null);
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _startTask() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);
      
      await supabase.from('tasks').update({
        'status': 'in_progress',
        'started_by': user?.id,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.task['id']);

      await supabase.from('task_activity').insert({
        'task_id': widget.task['id'],
        'staff_id': user?.id,
        'activity_type': 'started',
      });

      if (user != null) {
        try {
          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
          final staffName = staffNameRes?['name'] ?? 'Staff member';
          await ActivityLogger.log(
            supabase: supabase,
            customerId: widget.task['customer_id'],
            action: 'task_started',
            description: '$staffName started task ${widget.task['name']}',
            performedBy: user.id,
          );
        } catch (_) {}
      }
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task started!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markNotCompletedDialog() async {
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final taskId = widget.task['id'];

    final reasons = [
      'Customer Not Available',
      'Material Not Available',
      'Site Not Ready',
      'Weather Problem',
      'Technical Problem',
      'Permission Pending',
      'Customer Requested Delay',
      'Labour Not Available',
      'Other'
    ];

    String? selectedReason;
    final remarkController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('TASK NOT COMPLETED', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
                      items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      validator: (val) => val == null ? 'Please select a reason.' : null,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedReason = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: remarkController,
                      decoration: const InputDecoration(labelText: 'Additional Remark', border: OutlineInputBorder()),
                      maxLines: 2,
                      validator: (val) {
                        if (selectedReason == 'Other' && (val == null || val.trim().isEmpty)) {
                          return 'Please explain the reason.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final reason = selectedReason;
                      final remark = remarkController.text.trim();
                      Navigator.pop(context);
                      
                      setState(() => _isLoading = true);
                      try {
                        // 1. Get staff name
                        final staffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
                        final staffName = staffNameRes?['name'] ?? 'Staff member';

                        // 2. Update tasks table
                        await supabase.from('tasks').update({
                          'status': 'not_completed',
                          'not_completed_reason': reason,
                          'not_completed_remark': remark,
                          'not_completed_by': user?.id,
                          'not_completed_at': DateTime.now().toUtc().toIso8601String(),
                        }).eq('id', taskId);

                        // 3. Insert task activity record
                        await supabase.from('task_activity').insert({
                          'task_id': taskId,
                          'staff_id': user?.id,
                          'activity_type': 'not_completed',
                        });

                        // 4. Log activity
                        if (user != null) {
                          await ActivityLogger.log(
                            supabase: supabase,
                            customerId: widget.task['customer_id'],
                            action: 'task_not_completed',
                            description: '$staffName marked task ${widget.task['name']} as Not Completed (Reason: $reason)',
                            performedBy: user.id,
                          );
                        }

                        // 5. Notify Admins & Supervisors
                        final adminsResponse = await supabase.from('staff').select('id').inFilter('role', ['admin', 'supervisor']).eq('status', 'active');
                        final adminsList = List<Map<String, dynamic>>.from(adminsResponse);
                        for (var admin in adminsList) {
                          if (admin['id'] != user?.id) {
                            await supabase.from('notifications').insert({
                              'user_id': admin['id'],
                              'title': 'Task Not Completed',
                              'message': '$staffName could not complete:\n${widget.task['name']}\n\nReason:\n$reason',
                            });
                          }
                        }

                        ref.invalidate(taskDetailsProvider(taskId));
                        ref.invalidate(incompleteTaskListProvider);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Task marked as Not Completed.'), backgroundColor: Colors.orange),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('SUBMIT'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _markInProgress() async {
    setState(() => _isLoading = true);
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final taskId = widget.task['id'];

    try {
      await supabase.from('tasks').update({
        'status': 'in_progress',
        'started_by': user?.id,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', taskId);

      await supabase.from('task_activity').insert({
        'task_id': taskId,
        'staff_id': user?.id,
        'activity_type': 'started',
      });

      ref.invalidate(taskDetailsProvider(taskId));
      ref.invalidate(incompleteTaskListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task resumed. Status set to In Progress.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reassignStaffDialog() async {
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final taskId = widget.task['id'];

    setState(() => _isLoading = true);
    try {
      // 1. Fetch active staff
      final staffResponse = await supabase.from('staff').select('id, name, role').eq('status', 'active').order('name');
      final staffList = List<Map<String, dynamic>>.from(staffResponse);
      
      setState(() => _isLoading = false);
      if (!mounted) return;

      if (staffList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active staff found.')));
        return;
      }

      Map<String, dynamic>? selectedStaff;

      await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Reassign Task', style: TextStyle(fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Select new staff member to assign this task:', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedStaff,
                      hint: const Text('Select Staff...'),
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: staffList.map((s) {
                        return DropdownMenuItem(
                          value: s,
                          child: Text('${s['name']} (${s['role']})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedStaff = val;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                  ElevatedButton(
                    onPressed: selectedStaff == null
                        ? null
                        : () async {
                            Navigator.pop(context);
                            setState(() => _isLoading = true);
                            try {
                              final newStaffId = selectedStaff!['id'];
                              final newStaffName = selectedStaff!['name'];

                              // Get current admin staff name
                              final currentStaffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
                              final currentStaffName = currentStaffNameRes?['name'] ?? 'Admin';

                              // Update task_staff table (delete existing and insert new)
                              await supabase.from('task_staff').delete().eq('task_id', taskId);
                              await supabase.from('task_staff').insert({
                                'task_id': taskId,
                                'staff_id': newStaffId,
                              });

                              // Reset task to pending/in_progress if needed, log reassign
                              await supabase.from('tasks').update({
                                'status': 'in_progress',
                                'updated_at': DateTime.now().toUtc().toIso8601String(),
                              }).eq('id', taskId);

                              // Log reassign activity
                              await supabase.from('task_activity').insert({
                                'task_id': taskId,
                                'staff_id': user?.id,
                                'activity_type': 'reassigned',
                              });

                              // Notify new assigned staff
                              await supabase.from('notifications').insert({
                                'user_id': newStaffId,
                                'title': '🔔 New Task Assigned',
                                'message': 'You have been reassigned to task:\n${widget.task['name']}\n\nAssigned by:\n$currentStaffName',
                              });

                              ref.invalidate(taskDetailsProvider(taskId));
                              ref.invalidate(incompleteTaskListProvider);

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Task successfully reassigned to $newStaffName!'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to reassign: $e')));
                              }
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    child: const Text('REASSIGN'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _completeTask() async {
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final taskId = widget.task['id'];

    String? remark;
    PlatformFile? pickedFile;

    await showDialog(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Complete Task', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    const Text('COMPLETED', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Remark',
                        hintText: 'Enter completion remark...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    const Text('Completion Photo (Optional):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    if (pickedFile != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.image, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pickedFile!.name,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                pickedFile = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_a_photo),
                        label: const Text('ADD PHOTO'),
                        onPressed: () async {
                          try {
                            final result = await FilePicker.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (result != null && result.files.isNotEmpty) {
                              setDialogState(() {
                                pickedFile = result.files.first;
                              });
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error picking photo: $e')),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () {
                    remark = ctrl.text.trim();
                    Navigator.pop(context, 'submit');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text('COMPLETE TASK'),
                ),
              ],
            );
          },
        );
      },
    );

    if (remark == null) return;

    setState(() => _isLoading = true);
    try {
      if (pickedFile != null && pickedFile!.bytes != null) {
        final safeName = pickedFile!.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final uploadPath = '$taskId/attachment_completion_${DateTime.now().millisecondsSinceEpoch}_$safeName';

        await supabase.storage.from('task_attachments').uploadBinary(
          uploadPath,
          pickedFile!.bytes!,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );

        await supabase.from('task_attachments').insert({
          'task_id': taskId,
          'file_name': pickedFile!.name,
          'file_path': uploadPath,
          'file_type': 'photo',
          'file_size': pickedFile!.size,
          'uploaded_by': user?.id,
        });
      }

      await supabase.from('tasks').update({
        'status': 'completed',
        'completed_by': user?.id,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'completion_remark': remark,
      }).eq('id', taskId);

      await supabase.from('task_activity').insert({
        'task_id': taskId,
        'staff_id': user?.id,
        'activity_type': 'completed',
      });

      if (user != null) {
        try {
          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
          final staffName = staffNameRes?['name'] ?? 'Staff member';
          await ActivityLogger.log(
            supabase: supabase,
            customerId: widget.task['customer_id'],
            action: 'task_completed',
            description: '$staffName completed task ${widget.task['name']}',
            performedBy: user.id,
          );
        } catch (_) {}
      }
      
      ref.invalidate(taskDetailsProvider(taskId));

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task marked as completed!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTaskDate(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    try {
      final d = DateTime.parse(dateTimeStr).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return dateTimeStr;
    }
  }

  String _formatTaskTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    try {
      final d = DateTime.parse(dateTimeStr).toLocal();
      final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
      final amPm = d.hour >= 12 ? 'PM' : 'AM';
      final minutesStr = d.minute.toString().padLeft(2, '0');
      return '${hour.toString().padLeft(2, '0')}:$minutesStr $amPm';
    } catch (_) {
      return dateTimeStr;
    }
  }

  Future<void> _openAttachment(String name, String type, String filePath) async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final response = await supabase.storage.from('task_attachments').createSignedUrl(filePath, 60);
      
      if (type == 'photo') {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TaskFileViewerScreen(name: name, url: response),
            ),
          );
        }
      } else {
        final url = Uri.parse(response);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.inAppBrowserView);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open file viewer.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open file: $e')),
        );
      }
    }
  }

  Future<void> _deleteAttachment(String attachmentId, String filePath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attachment'),
        content: const Text('Are you sure you want to delete this attachment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.storage.from('task_attachments').remove([filePath]);
      await supabase.from('task_attachments').delete().eq('id', attachmentId);
      ref.invalidate(taskDetailsProvider(widget.task['id']));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment deleted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete attachment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadAttachment(String type) async {
    try {
      final result = await FilePicker.pickFiles(
        type: type == 'pdf' ? FileType.custom : FileType.image,
        allowedExtensions: type == 'pdf' ? ['pdf'] : null,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      setState(() => _isLoading = true);
      
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);
      final taskId = widget.task['id'];
      
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final uploadPath = '$taskId/attachment_${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await supabase.storage.from('task_attachments').uploadBinary(
        uploadPath,
        file.bytes!,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );

      await supabase.from('task_attachments').insert({
        'task_id': taskId,
        'file_name': file.name,
        'file_path': uploadPath,
        'file_type': type,
        'file_size': file.size,
        'uploaded_by': user?.id,
      });

      ref.invalidate(taskDetailsProvider(taskId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment uploaded successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload attachment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _whatsappTask(Map<String, dynamic> task, Map<String, dynamic>? customer, String status) async {
    final mobile = customer?['mobile'];
    if (mobile == null || mobile.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No mobile number available for WhatsApp.')));
      return;
    }
    
    final message = "Customer Name: ${customer?['name'] ?? 'N/A'}\n"
        "Customer ID: ${customer?['customer_id'] ?? 'N/A'}\n"
        "Task Name: ${task['name'] ?? 'N/A'}\n"
        "Task Status: ${status.toUpperCase()}";
        
    final Uri url = Uri.parse("https://wa.me/91$mobile?text=${Uri.encodeComponent(message)}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch WhatsApp')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskAsync = ref.watch(taskDetailsProvider(widget.task['id']));
    final roleAsync = ref.watch(userRoleProvider);
    final userRole = roleAsync.value ?? '';

    return taskAsync.when(
      data: (task) {
        final status = task['status'] ?? 'pending';
        final customer = task['customers'] as Map<String, dynamic>?;
        final completerName = task['completer_name'];
        final assignedStaff = (task['assigned_staff'] as List?) ?? [];
        final activities = (task['activity'] as List?) ?? [];
        final attachments = (task['attachments'] as List?) ?? [];

        return Scaffold(
          appBar: AppBar(
            title: const Text('TASK DETAILS'),
            actions: [
              IconButton(
                icon: const Icon(Icons.share, color: Colors.blue),
                tooltip: 'Share',
                onPressed: () async {
                  final List<String> names = (task['assigned_staff_names'] as List?)?.cast<String>() ?? [];
                  final staffNames = names.join(', ');
                  final shareText = "Task: ${task['name'] ?? 'N/A'}\n"
                      "Customer Name: ${customer?['name'] ?? 'N/A'}\n"
                      "PM Surya Ghar Application ID: ${customer?['pm_surya_ghar_application_id'] ?? 'N/A'}\n"
                      "Task Status: ${status.toUpperCase()}\n"
                      "Assigned Staff: ${staffNames.isNotEmpty ? staffNames : 'None'}";
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Task Name & Priority Header
                Text(
                  task['name'] ?? '',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _buildPriorityBadge(task['priority']),
                const SizedBox(height: 20),

                // 2. Clickable Customer details card
                const Text('Customer', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (customer != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)));
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(customer?['name'] ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                          const SizedBox(height: 4),
                          Text('ID: ${customer?['customer_id'] ?? 'N/A'}', style: TextStyle(color: Colors.grey.shade700)),
                          const SizedBox(height: 2),
                          Text('Mobile: ${customer?['mobile'] ?? 'N/A'}', style: TextStyle(color: Colors.grey.shade700)),
                          if (customer?['consumer_number'] != null) ...[
                            const SizedBox(height: 2),
                            Text('Consumer No: ${customer?['consumer_number']}', style: TextStyle(color: Colors.grey.shade700)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Description
                const Text('Description', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      task['description'] ?? 'No description provided.',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Status Dot
                const Text('STATUS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                _buildStatusRow(status),
                const SizedBox(height: 20),

                // 5. Assigned Staff
                const Text('ASSIGNED STAFF', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: assignedStaff.isEmpty
                          ? [const Text('No staff assigned.', style: TextStyle(color: Colors.grey))]
                          : assignedStaff.map((staff) {
                              final staffName = staff['name'] ?? 'Unknown';
                              final photoUrl = staff['profile_photo_url'] as String?;
                              final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                                      backgroundColor: hasPhoto ? Colors.transparent : Colors.blue.shade100,
                                      child: hasPhoto ? null : Text(
                                        staffName.isNotEmpty ? staffName[0].toUpperCase() : 'S',
                                        style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(staffName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              );
                            }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 5.5 Assigner Staff
                const Text('ASSIGNER STAFF', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildCreatorRow(task['creator'] as Map<String, dynamic>?),
                  ),
                ),
                const SizedBox(height: 20),

                // 6. Activity Timeline
                const Text('ACTIVITY', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: activities.isEmpty
                        ? const Text('No activity logged yet.', style: TextStyle(color: Colors.grey))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: activities.map((activity) {
                              final timeStr = _formatTaskTime(activity['created_at']);
                              final type = activity['activity_type'];
                              final staffName = activity['staff_name'] ?? 'Unknown';
                              final photoUrl = activity['staff_profile_photo_url'] as String?;
                              final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                                      backgroundColor: hasPhoto ? Colors.transparent : Colors.blue.shade100,
                                      child: hasPhoto ? null : Text(
                                        staffName.isNotEmpty ? staffName[0].toUpperCase() : 'S',
                                        style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$timeStr  $staffName $type task',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // 6.5 Attachments
                const Text('ATTACHMENTS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (attachments.isEmpty)
                          const Text('No attachments yet.', style: TextStyle(color: Colors.grey))
                        else
                          Column(
                            children: attachments.map((att) {
                              final name = att['file_name'] ?? 'File';
                              final path = att['file_path'] as String;
                              final type = att['file_type'] ?? 'other';
                              final size = att['file_size'] as int? ?? 0;
                              final uploader = att['uploader_name'] ?? 'System';
                              final createdAt = att['created_at'];
                              final isPdf = type == 'pdf';
                              final sizeKb = (size / 1024).toStringAsFixed(1);
                              
                              final loggedInUser = ref.read(currentUserProvider);
                              final isAdmin = ref.read(userRoleProvider).value == 'admin';
                              final canDelete = isAdmin || (loggedInUser != null && loggedInUser.id == att['uploaded_by']);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.image, color: Colors.blue),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: Text('By $uploader on ${_formatTaskDate(createdAt)} • $sizeKb KB'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.open_in_new, color: Colors.blue),
                                      tooltip: 'Open',
                                      onPressed: () => _openAttachment(name, type, path),
                                    ),
                                    if (canDelete)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        tooltip: 'Delete',
                                        onPressed: () => _deleteAttachment(att['id'], path),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        if (ref.read(userRoleProvider).value == 'admin' || assignedStaff.any((s) => s['name'] == ref.read(currentUserProvider)?.email)) ...[
                          const Divider(),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _pickAndUploadAttachment('pdf'),
                                icon: const Icon(Icons.picture_as_pdf, size: 16),
                                label: const Text('Add PDF', style: TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => _pickAndUploadAttachment('photo'),
                                icon: const Icon(Icons.add_a_photo, size: 16),
                                label: const Text('Add Photo', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 7. Completion card
                if (status == 'completed') ...[
                  const Text('COMPLETION', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Card(
                    margin: EdgeInsets.zero,
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Completed By: ${completerName ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Date: ${_formatTaskDate(task['completed_at'])}'),
                          Text('Time: ${_formatTaskTime(task['completed_at'])}'),
                          if (task['completion_remark'] != null) ...[
                            const SizedBox(height: 8),
                            const Text('Completion Remark:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(task['completion_remark']),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 7.5 Incomplete details card
                if (status == 'not_completed') ...[
                  const Text('TASK NOT COMPLETED DETAILS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Card(
                    margin: EdgeInsets.zero,
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Not Completed By: ${task['not_completed_by_name'] ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Date: ${_formatTaskDate(task['not_completed_at'])}'),
                          Text('Time: ${_formatTaskTime(task['not_completed_at'])}'),
                          const SizedBox(height: 8),
                          Text('Reason: ${task['not_completed_reason'] ?? 'N/A'}', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                          if (task['not_completed_remark'] != null && task['not_completed_remark'].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text('Remark:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(task['not_completed_remark']),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 8. Action Buttons
                if (status == 'pending') ...[
                  ElevatedButton(
                    onPressed: _isLoading ? null : _startTask,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('START TASK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                ] else if (status == 'in_progress') ...[
                  ElevatedButton(
                    onPressed: _isLoading ? null : _completeTask,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('COMPLETE TASK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _markNotCompletedDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('NOT COMPLETED', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                ] else if (status == 'not_completed') ...[
                  Builder(
                    builder: (context) {
                      final isAdminOrSupervisor = userRole == 'admin' || userRole == 'supervisor';
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _isLoading ? null : _markInProgress,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('MARK IN PROGRESS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 12),
                          if (isAdminOrSupervisor) ...[
                            ElevatedButton(
                              onPressed: _isLoading ? null : _reassignStaffDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('REASSIGN TASK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _completeTask,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('COMPLETE TASK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      );
                    }
                  ),
                ],

                // 9. WhatsApp Button (always shown)
                OutlinedButton.icon(
                  onPressed: () => _whatsappTask(task, customer, status),
                  icon: const Icon(Icons.share, color: Colors.green),
                  label: const Text('WHATSAPP', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('TASK DETAILS')),
        body: Center(child: Text('Error loading task details: $e')),
      ),
    );
  }

  Widget _buildPriorityBadge(String? priority) {
    String label = 'Normal';
    Color c = Colors.amber;
    String emoji = '🟡';
    
    if (priority == 'high') {
      label = 'High';
      c = Colors.red;
      emoji = '🟠';
    } else if (priority == 'low') {
      label = 'Low';
      c = Colors.green;
      emoji = '🟢';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String status) {
    Color color;
    String label;
    
    switch (status) {
      case 'completed':
        color = Colors.green;
        label = 'Completed';
        break;
      case 'in_progress':
        color = Colors.blue;
        label = 'In Progress';
        break;
      case 'not_completed':
        color = Colors.red;
        label = 'Not Completed';
        break;
      default:
        color = Colors.orange;
        label = 'Pending';
    }

    return Row(
      children: [
        Text(
          '● ',
          style: TextStyle(color: color, fontSize: 20),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildCreatorRow(Map<String, dynamic>? creator) {
    if (creator == null) {
      return const Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.grey,
            child: Icon(Icons.person, size: 12, color: Colors.white),
          ),
          SizedBox(width: 8),
          Text('System / Unknown Assigner', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      );
    }
    final name = creator['name'] ?? 'Unknown';
    final photoUrl = creator['profile_photo_url'] as String?;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
          backgroundColor: hasPhoto ? Colors.transparent : Colors.blue.shade100,
          child: hasPhoto ? null : Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'S',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
