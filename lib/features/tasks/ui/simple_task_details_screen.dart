import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'widgets/simple_task_header.dart';
import 'widgets/incomplete_reason_dialog.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/notifications/notification_state.dart';

class SimpleTaskDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;

  const SimpleTaskDetailsScreen({super.key, required this.task});

  @override
  ConsumerState<SimpleTaskDetailsScreen> createState() => _SimpleTaskDetailsScreenState();
}

class _SimpleTaskDetailsScreenState extends ConsumerState<SimpleTaskDetailsScreen> {
  bool _isLoading = false;
  late String _selectedStatus;
  String? _incompleteReason;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.task['status']?.toString() ?? 'pending';
    _incompleteReason = widget.task['incomplete_reason']?.toString();
  }

  Future<void> _handleNotCompleted() async {
    final reason = await IncompleteReasonDialog.show(context);
    if (reason != null) {
      setState(() {
        _selectedStatus = 'not_completed';
        _incompleteReason = reason;
      });
    }
  }

  Future<void> _saveStatus() async {
    setState(() => _isLoading = true);
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final taskId = widget.task['id'] ?? widget.task['task_id'];
    final customerId = widget.task['customer_id'] ?? '';
    final taskName = widget.task['name'] ?? 'Task';

    try {
      final Map<String, dynamic> updates = {
        'status': _selectedStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (_selectedStatus == 'completed') {
        updates['completed_by'] = user?.id;
        updates['completed_at'] = DateTime.now().toUtc().toIso8601String();
        updates['incomplete_reason'] = null;
      } else if (_selectedStatus == 'not_completed') {
        updates['incomplete_marked_by'] = user?.id;
        updates['incomplete_at'] = DateTime.now().toUtc().toIso8601String();
        updates['incomplete_reason'] = _incompleteReason;
      } else if (_selectedStatus == 'in_progress') {
        updates['started_by'] = user?.id;
        updates['started_at'] = DateTime.now().toUtc().toIso8601String();
        updates['incomplete_reason'] = null;
      } else {
        // pending
        updates['incomplete_reason'] = null;
      }

      await supabase.from('tasks').update(updates).eq('id', taskId);

      // Log activity
      String logAction = 'task_updated';
      String logDesc = 'Task updated to $_selectedStatus';
      if (_selectedStatus == 'completed') {
        logAction = 'task_completed';
        logDesc = 'Task completed.';
      } else if (_selectedStatus == 'not_completed') {
        logAction = 'task_not_completed';
        logDesc = 'Task marked not completed: $_incompleteReason';
      } else if (_selectedStatus == 'in_progress') {
        logAction = 'task_started';
        logDesc = 'Task started.';
      }

      await ActivityLogger.log(
        supabase: supabase,
        customerId: customerId,
        action: logAction,
        description: logDesc,
        performedBy: user?.id,
      );

      // Notify admins
      final notificationRepo = ref.read(notificationRepositoryProvider);
      if (_selectedStatus == 'completed') {
        await notificationRepo.notifyAdmins(
          notificationType: 'TASK_COMPLETED',
          title: '✅ Task Completed',
          message: '$taskName completed by ${user?.email ?? "Staff"}.',
          relatedRecordId: taskId,
        );
      } else if (_selectedStatus == 'not_completed') {
        await notificationRepo.notifyAdmins(
          notificationType: 'TASK_INCOMPLETE',
          title: '⚠ Task Not Completed',
          message: '$taskName marked incomplete. Reason: $_incompleteReason',
          relatedRecordId: taskId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task status saved successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving task status: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SimpleTaskHeader(
                    task: widget.task,
                    status: _selectedStatus,
                  ),
                  const SizedBox(height: 16),
                  
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UPDATE TASK STATUS',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 16),
                          
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(
                                    child: Text('START', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  selected: _selectedStatus == 'in_progress',
                                  selectedColor: Colors.blue.shade100,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _selectedStatus = 'in_progress';
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(
                                    child: Text('COMPLETE', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  selected: _selectedStatus == 'completed',
                                  selectedColor: Colors.green.shade100,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _selectedStatus = 'completed';
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(
                                    child: Text('INCOMPLETE', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  selected: _selectedStatus == 'not_completed',
                                  selectedColor: Colors.red.shade100,
                                  onSelected: (selected) {
                                    if (selected) {
                                      _handleNotCompleted();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          
                          if (_selectedStatus == 'not_completed' && _incompleteReason != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning, color: Colors.red, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Reason: $_incompleteReason',
                                      style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  ElevatedButton(
                    onPressed: _saveStatus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
    );
  }
}
