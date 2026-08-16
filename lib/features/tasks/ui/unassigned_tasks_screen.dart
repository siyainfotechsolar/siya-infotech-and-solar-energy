import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/task_provider.dart';
import '../../../core/notifications/notification_state.dart';
import 'task_details_screen.dart';

class UnassignedTasksScreen extends ConsumerStatefulWidget {
  const UnassignedTasksScreen({super.key});

  @override
  ConsumerState<UnassignedTasksScreen> createState() => _UnassignedTasksScreenState();
}

class _UnassignedTasksScreenState extends ConsumerState<UnassignedTasksScreen> {
  bool _isAssigning = false;

  Future<void> _assignStaffDialog(Map<String, dynamic> task) async {
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final taskId = task['id'];

    setState(() => _isAssigning = true);

    try {
      final staffResponse = await supabase
          .from('staff')
          .select('id, name, role')
          .eq('status', 'active')
          .order('name');
      
      final staffList = List<Map<String, dynamic>>.from(staffResponse);

      setState(() => _isAssigning = false);
      if (!mounted) return;

      if (staffList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active staff available.')));
        return;
      }

      final List<String> selectedStaffIds = [];

      await showDialog(
        context: context,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('ASSIGN STAFF', style: TextStyle(fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Task: ${task['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Customer: ${(task['customers'] as Map?)?['name'] ?? 'N/A'}'),
                      const SizedBox(height: 16),
                      const Text('Select staff member(s):', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: staffList.map((s) {
                          final id = s['id'] as String;
                          final isSelected = selectedStaffIds.contains(id);
                          return FilterChip(
                            label: Text('${s['name']} (${s['role']})'),
                            selected: isSelected,
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedStaffIds.add(id);
                                } else {
                                  selectedStaffIds.remove(id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    onPressed: selectedStaffIds.isEmpty
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(this.context);
                            Navigator.pop(dialogCtx);
                            setState(() => _isAssigning = true);

                            try {
                              final mappings = selectedStaffIds.map((sid) => {
                                'task_id': taskId,
                                'staff_id': sid,
                              }).toList();

                              await supabase.from('task_staff').insert(mappings);

                              String adminName = 'Admin';
                              if (user != null) {
                                try {
                                  final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
                                  if (staffNameRes?['name'] != null) adminName = staffNameRes!['name'];
                                } catch (_) {}
                              }

                              final notificationRepo = ref.read(notificationRepositoryProvider);
                              for (final sid in selectedStaffIds) {
                                try {
                                  await notificationRepo.sendNotification(
                                    recipientUserId: sid,
                                    notificationType: 'TASK_ASSIGNED',
                                    title: '🔔 New Task Assigned',
                                    message: 'You have been assigned to task:\n${task['name']}\n\nAssigned by:\n$adminName',
                                    taskId: taskId,
                                  );
                                } catch (_) {}
                              }

                              ref.invalidate(taskListProvider);

                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Staff assigned successfully!'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                messenger.showSnackBar(SnackBar(content: Text('Error assigning staff: $e')));
                              }
                            } finally {
                              if (mounted) setState(() => _isAssigning = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    child: const Text('ASSIGN'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      setState(() => _isAssigning = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('UNASSIGNED TASKS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(taskListProvider),
          ),
        ],
      ),
      body: tasksAsync.when(
        data: (allTasks) {
          final unassigned = allTasks.where((t) {
            final ts = t['task_staff'] as List?;
            return ts == null || ts.isEmpty;
          }).toList();

          if (unassigned.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                  SizedBox(height: 12),
                  Text('No unassigned tasks found!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('All installation tasks have assigned staff members.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: unassigned.length,
            itemBuilder: (context, idx) {
              final task = unassigned[idx];
              final customer = task['customers'] as Map?;
              final customerName = customer?['name'] ?? 'N/A';
              final customerId = customer?['customer_id'] ?? 'N/A';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.shade300),
                ),
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              task['name'] ?? 'Task',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(8)),
                            child: const Text('UNASSIGNED', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Customer: $customerName (ID: $customerId)', style: TextStyle(color: Colors.grey.shade800)),
                      if (task['description'] != null && task['description'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Desc: ${task['description']}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(task: task))),
                            icon: const Icon(Icons.info_outline, size: 16),
                            label: const Text('Details'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isAssigning ? null : () => _assignStaffDialog(task),
                            icon: const Icon(Icons.person_add_alt_1, size: 16),
                            label: const Text('ASSIGN STAFF'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading unassigned tasks: $e')),
      ),
    );
  }
}
