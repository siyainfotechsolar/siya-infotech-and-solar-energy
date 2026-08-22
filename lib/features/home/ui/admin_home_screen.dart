import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../customers/ui/customer_details_screen.dart';
import '../../customers/ui/add_customer_screen.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../tasks/ui/add_task_screen.dart';
import '../../staff/ui/staff_list_screen.dart';
import '../../more/ui/audit_log_screen.dart';
import '../../../core/notifications/notification_state.dart';
import '../../notifications/ui/notifications_screen.dart';
import '../../../core/utils/priority_calculator.dart';

// Combined metrics provider for fast single-query loading
final adminHomeMetricsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);

  try {
    final results = await Future.wait([
      supabase.from('customers').select('id'),
      supabase.from('tasks').select('id').eq('status', 'pending'),
      supabase.from('tasks').select('id').eq('status', 'in_progress'),
      supabase.from('tasks').select('id').eq('status', 'completed'),
      supabase.from('tasks').select('id').eq('status', 'not_completed'),
      supabase.from('staff').select('id'),
    ]);

    int loanOfficeFileReady = 0;
    int loanPrinted = 0;
    int loanSentToBank = 0;
    int loan1stStage = 0;
    int loan2ndStage = 0;
    int loanApproved = 0;
    int loanRejected = 0;
    int loanOpenProblems = 0;

    int highPriorityCount = 0;
    int mediumPriorityCount = 0;

    try {
      final loanResults = await Future.wait([
        supabase.from('customers').select('id').eq('loan_stage', 'OFFICE FILE READY'),
        supabase.from('customers').select('id').eq('loan_stage', 'PRINTED'),
        supabase.from('customers').select('id').eq('loan_stage', 'SENT TO BANK'),
        supabase.from('customers').select('id').eq('loan_stage', '1ST STAGE'),
        supabase.from('customers').select('id').eq('loan_stage', '2ND STAGE'),
        supabase.from('customers').select('id').eq('loan_stage', 'APPROVED'),
        supabase.from('customers').select('id').eq('loan_stage', 'REJECTED'),
        supabase.from('customers').select('id').eq('loan_issue_status', 'OPEN PROBLEM'),
      ]);

      loanOfficeFileReady = (loanResults[0] as List).length;
      loanPrinted = (loanResults[1] as List).length;
      loanSentToBank = (loanResults[2] as List).length;
      loan1stStage = (loanResults[3] as List).length;
      loan2ndStage = (loanResults[4] as List).length;
      loanApproved = (loanResults[5] as List).length;
      loanRejected = (loanResults[6] as List).length;
      loanOpenProblems = (loanResults[7] as List).length;
    } catch (_) {
      // Loan columns don't exist yet, fallback to 0 to prevent crashes
    }

    try {
      final priorityResults = await Future.wait([
        supabase.from('customers').select('created_at, last_meaningful_update, loan_issue_status, manual_priority, tasks(status), site_installation_tasks(status)'),
        supabase.from('leads').select('created_at, last_meaningful_update, manual_priority').neq('status', 'converted'),
      ]);

      // Process Customers
      for (var c in (priorityResults[0] as List)) {
        final createdAt = c['created_at'] != null ? DateTime.tryParse(c['created_at']) : null;
        final lastUpdate = c['last_meaningful_update'] != null ? DateTime.tryParse(c['last_meaningful_update']) : null;
        final loanIssueStatus = c['loan_issue_status'] as String?;
        final tasksList = [
          ...(c['tasks'] as List? ?? []),
          ...(c['site_installation_tasks'] as List? ?? []),
        ];

        final automatic = PriorityCalculator.calculateAutomatic(
          createdAt: createdAt,
          lastMeaningfulUpdate: lastUpdate,
          loanIssueStatus: loanIssueStatus,
          tasks: tasksList,
        );
        final manual = c['manual_priority'] as String?;
        final finalPriority = PriorityCalculator.calculateFinal(automatic: automatic, manual: manual);

        if (finalPriority == 'HIGH') {
          highPriorityCount++;
        } else if (finalPriority == 'MEDIUM') {
          mediumPriorityCount++;
        }
      }

      // Process Leads
      for (var l in (priorityResults[1] as List)) {
        final createdAt = l['created_at'] != null ? DateTime.tryParse(l['created_at']) : null;
        final lastUpdate = l['last_meaningful_update'] != null ? DateTime.tryParse(l['last_meaningful_update']) : null;

        final automatic = PriorityCalculator.calculateAutomatic(
          createdAt: createdAt,
          lastMeaningfulUpdate: lastUpdate,
          loanIssueStatus: null,
          tasks: const [],
        );
        final manual = l['manual_priority'] as String?;
        final finalPriority = PriorityCalculator.calculateFinal(automatic: automatic, manual: manual);

        if (finalPriority == 'HIGH') {
          highPriorityCount++;
        } else if (finalPriority == 'MEDIUM') {
          mediumPriorityCount++;
        }
      }
    } catch (_) {
      // Priority/Leads columns don't exist yet, fallback to 0
    }

    return {
      'customers': (results[0] as List).length,
      'pendingTasks': (results[1] as List).length,
      'inProgressTasks': (results[2] as List).length,
      'completedTasks': (results[3] as List).length,
      'incompleteTasks': (results[4] as List).length,
      'staff': (results[5] as List).length,
      'loanOfficeFileReady': loanOfficeFileReady,
      'loanPrinted': loanPrinted,
      'loanSentToBank': loanSentToBank,
      'loan1stStage': loan1stStage,
      'loan2ndStage': loan2ndStage,
      'loanApproved': loanApproved,
      'loanRejected': loanRejected,
      'loanOpenProblems': loanOpenProblems,
      'highPriority': highPriorityCount,
      'mediumPriority': mediumPriorityCount,
    };
  } catch (e) {
    rethrow;
  }
});

// Follow-up Today provider
final adminFollowupTodayProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final nowStr = DateTime.now().toIso8601String().split('T').first;

  try {
    final results = await Future.wait([
      supabase.from('customers').select('id, name, created_at, last_meaningful_update, loan_issue_status, manual_priority, next_followup_date, tasks(status), site_installation_tasks(status)'),
      supabase.from('leads').select('id, name, created_at, last_meaningful_update, manual_priority, next_followup_date').neq('status', 'converted'),
    ]);

    final List<Map<String, dynamic>> followupTodayList = [];

    // Process Customers
    for (var c in (results[0] as List)) {
      if (c['next_followup_date'] != null) {
        final followupDateStr = c['next_followup_date'].toString();
        if (followupDateStr.compareTo(nowStr) <= 0) {
          final createdAt = c['created_at'] != null ? DateTime.tryParse(c['created_at']) : null;
          final lastUpdate = c['last_meaningful_update'] != null ? DateTime.tryParse(c['last_meaningful_update']) : null;
          final loanIssueStatus = c['loan_issue_status'] as String?;
          final tasksList = [
            ...(c['tasks'] as List? ?? []),
            ...(c['site_installation_tasks'] as List? ?? []),
          ];

          final automatic = PriorityCalculator.calculateAutomatic(
            createdAt: createdAt,
            lastMeaningfulUpdate: lastUpdate,
            loanIssueStatus: loanIssueStatus,
            tasks: tasksList,
          );
          final manual = c['manual_priority'] as String?;
          final finalPriority = PriorityCalculator.calculateFinal(automatic: automatic, manual: manual);

          followupTodayList.add({
            'id': c['id'],
            'name': c['name'] ?? 'Unknown',
            'priority': finalPriority,
            'isLead': false,
            'customer': c,
          });
        }
      }
    }

    // Process Leads
    for (var l in (results[1] as List)) {
      if (l['next_followup_date'] != null) {
        final followupDateStr = l['next_followup_date'].toString();
        if (followupDateStr.compareTo(nowStr) <= 0) {
          final createdAt = l['created_at'] != null ? DateTime.tryParse(l['created_at']) : null;
          final lastUpdate = l['last_meaningful_update'] != null ? DateTime.tryParse(l['last_meaningful_update']) : null;

          final automatic = PriorityCalculator.calculateAutomatic(
            createdAt: createdAt,
            lastMeaningfulUpdate: lastUpdate,
            loanIssueStatus: null,
            tasks: const [],
          );
          final manual = l['manual_priority'] as String?;
          final finalPriority = PriorityCalculator.calculateFinal(automatic: automatic, manual: manual);

          followupTodayList.add({
            'id': l['id'],
            'name': l['name'] ?? 'Unknown',
            'priority': finalPriority,
            'isLead': true,
            'customer': l,
          });
        }
      }
    }

    return followupTodayList;
  } catch (_) {
    return [];
  }
});

final recentActivityProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final response = await supabase
      .from('audit_logs')
      .select('*, staff(name)')
      .order('timestamp', ascending: false)
      .limit(3);
  return List<Map<String, dynamic>>.from(response);
});

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  String _timeAgo(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      final d = DateTime.parse(dateTimeStr).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours} hr ago';
      if (diff.inDays == 1) return 'Yesterday';
      return '${diff.inDays} days ago';
    } catch (_) {
      return '';
    }
  }

  String _formatActivitySummary(Map<String, dynamic> log) {
    final action = (log['action'] as String? ?? '').toLowerCase();
    final staffName = (log['staff'] as Map?)?['name'] ?? 'Staff';
    final details = log['details'] as Map? ?? {};
    
    if (action.contains('create') && action.contains('customer')) {
      final name = details['customer_name'] ?? details['name'] ?? 'New Customer';
      return 'New customer "$name" added by $staffName';
    }
    if (action.contains('update') && action.contains('customer')) {
      final name = details['customer_name'] ?? details['name'] ?? 'Customer';
      return 'Customer "$name" details updated by $staffName';
    }
    if (action.contains('create') && action.contains('task')) {
      final name = details['task_name'] ?? details['name'] ?? 'New Task';
      return 'Task "$name" created by $staffName';
    }
    if (action.contains('complete') && action.contains('task')) {
      final name = details['task_name'] ?? details['name'] ?? 'Task';
      return 'Task "$name" completed by $staffName';
    }
    if (action.contains('dispatch') || action.contains('delivery')) {
      return 'Material delivery status updated by $staffName';
    }
    return '${log['action'] ?? 'Activity'} by $staffName';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(adminHomeMetricsProvider);
    final activityAsync = ref.watch(recentActivityProvider);
    final profileAsync = ref.watch(currentStaffProfileProvider);

    final adminName = profileAsync.when(
      data: (p) => (p?['name'] as String?)?.isNotEmpty == true ? p!['name'] : 'Admin',
      loading: () => 'Admin',
      error: (_, __) => 'Admin',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Good Morning, $adminName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          const _NotificationBell(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(adminHomeMetricsProvider);
              ref.invalidate(recentActivityProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminHomeMetricsProvider);
          ref.invalidate(recentActivityProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ref.watch(adminFollowupTodayProvider).when(
                data: (list) {
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Card(
                    color: Colors.red.shade50,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.red.shade200, width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.push_pin, color: Colors.red, size: 18),
                              SizedBox(width: 6),
                              Text(
                                '📌 FOLLOW-UP TODAY',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.redAccent),
                          ...list.map((item) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CustomerDetailsScreen(customer: item['customer'] as Map<String, dynamic>),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['name'] as String,
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item['priority']} Priority',
                                            style: TextStyle(
                                              color: item['priority'] == 'HIGH' ? Colors.red : Colors.orange,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: Colors.redAccent, size: 20),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              metricsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Failed to load metrics', style: TextStyle(color: Colors.red)),
                        TextButton(
                          onPressed: () => ref.invalidate(adminHomeMetricsProvider),
                          child: const Text('RETRY'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (m) {
                  final customersCount = m['customers'] ?? 0;
                  final pendingCount = m['pendingTasks'] ?? 0;
                  final inProgressCount = m['inProgressTasks'] ?? 0;
                  final completedCount = m['completedTasks'] ?? 0;
                  final incompleteCount = m['incompleteTasks'] ?? 0;
                  final activeCount = pendingCount + inProgressCount + incompleteCount;
                  final staffCount = m['staff'] ?? 0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- MAIN SUMMARY (2 large cards) ---
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              title: '👥 CUSTOMERS',
                              value: '$customersCount',
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen())),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              title: '📋 TASKS',
                              value: '$activeCount',
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // --- TASK STATUS (4 compact cards) ---
                      const Text(
                        'TASK STATUS',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _StatusCard(
                              label: '⏳ PENDING',
                              value: '$pendingCount',
                              color: Colors.orange,
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const TaskListScreen(initialIndex: 0, initialStatusFilter: 'pending'),
                              )),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatusCard(
                              label: '🔄 PROGRESS',
                              value: '$inProgressCount',
                              color: Colors.blue,
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const TaskListScreen(initialIndex: 0, initialStatusFilter: 'in_progress'),
                              )),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatusCard(
                              label: '✅ COMPLETED',
                              value: '$completedCount',
                              color: Colors.green,
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const TaskListScreen(initialIndex: 1, initialStatusFilter: 'completed'),
                              )),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatusCard(
                              label: '⚠️ INCOMPLETE',
                              value: '$incompleteCount',
                              color: Colors.red,
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const TaskListScreen(initialIndex: 0, initialStatusFilter: 'not_completed'),
                              )),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // --- ATTENTION REQUIRED / PRIORITY CUSTOMERS ---
                      Card(
                        elevation: 1,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.red.shade100, width: 1),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Column(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const CustomerListScreen(
                                          initialPriorityFilter: 'ALL',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '⚠ PRIORITY CUSTOMERS',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                                        ),
                                        Icon(Icons.chevron_right, size: 20, color: Colors.red),
                                      ],
                                    ),
                                  ),
                                ),
                                const Divider(),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.red,
                                    radius: 14,
                                    child: Text('🔴', style: TextStyle(fontSize: 12)),
                                  ),
                                  title: const Text('High Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
                                        child: Text(
                                          '${m['highPriority'] ?? 0}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const CustomerListScreen(
                                          initialPriorityFilter: 'HIGH',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.orange,
                                    radius: 14,
                                    child: Text('🟠', style: TextStyle(fontSize: 12)),
                                  ),
                                  title: const Text('Medium Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
                                        child: Text(
                                          '${m['mediumPriority'] ?? 0}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const CustomerListScreen(
                                          initialPriorityFilter: 'MEDIUM',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- QUICK ACTIONS ---
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerScreen())),
                              icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                              label: const Text('ADD CUSTOMER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddTaskScreen())),
                              icon: const Icon(Icons.add_task_outlined, size: 16),
                              label: const Text('CREATE TASK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // --- STAFF SUMMARY ---
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffListScreen())),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('👷 ', style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'STAFF (Total: $staffCount)',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.chevron_right, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // --- LOAN SUMMARY (Expandable) ---
                      const SizedBox(height: 20),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        clipBehavior: Clip.antiAlias,
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            leading: const Icon(Icons.account_balance, color: Colors.blue),
                            title: const Text(
                              '🏦 LOAN STATUS',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              _buildLoanSummaryRow(
                                context,
                                label: 'Office File Ready',
                                count: m['loanOfficeFileReady'] ?? 0,
                                loanStage: 'OFFICE FILE READY',
                              ),
                              _buildLoanSummaryRow(
                                context,
                                label: 'Printed',
                                count: m['loanPrinted'] ?? 0,
                                loanStage: 'PRINTED',
                              ),
                              _buildLoanSummaryRow(
                                context,
                                label: 'Sent To Bank',
                                count: m['loanSentToBank'] ?? 0,
                                loanStage: 'SENT TO BANK',
                              ),
                              _buildLoanSummaryRow(
                                context,
                                label: '1st Stage',
                                count: m['loan1stStage'] ?? 0,
                                loanStage: '1ST STAGE',
                              ),
                              _buildLoanSummaryRow(
                                context,
                                label: '2nd Stage',
                                count: m['loan2ndStage'] ?? 0,
                                loanStage: '2ND STAGE',
                              ),
                              _buildLoanSummaryRow(
                                context,
                                label: 'Approved',
                                count: m['loanApproved'] ?? 0,
                                loanStage: 'APPROVED',
                                isPositive: true,
                              ),
                              _buildLoanSummaryRow(
                                context,
                                label: 'Rejected',
                                count: m['loanRejected'] ?? 0,
                                loanStage: 'REJECTED',
                                isNegative: true,
                              ),
                              const Divider(height: 20),
                              _buildLoanSummaryRow(
                                context,
                                label: '⚠ Open Problems',
                                count: m['loanOpenProblems'] ?? 0,
                                loanIssueStatus: 'OPEN PROBLEM',
                                isWarning: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // --- RECENT ACTIVITY ---
              activityAsync.when(
                loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                error: (e, _) => Text('Error loading activity: $e', style: const TextStyle(color: Colors.red, fontSize: 13)),
                data: (logs) {
                  if (logs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogScreen())),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'RECENT ACTIVITY',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                                ),
                                Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...logs.map((log) {
                              final summary = _formatActivitySummary(log);
                              final time = _timeAgo(log['timestamp']);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(summary, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                          if (time.isNotEmpty)
                                            Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoanSummaryRow(
    BuildContext context, {
    required String label,
    required int count,
    String? loanStage,
    String? loanIssueStatus,
    bool isPositive = false,
    bool isNegative = false,
    bool isWarning = false,
  }) {
    Color badgeColor = Colors.grey.shade100;
    Color textColor = Colors.black87;
    if (isPositive) {
      badgeColor = Colors.green.shade50;
      textColor = Colors.green.shade700;
    } else if (isNegative) {
      badgeColor = Colors.red.shade50;
      textColor = Colors.red.shade700;
    } else if (isWarning) {
      badgeColor = Colors.orange.shade50;
      textColor = Colors.orange.shade800;
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerListScreen(
              initialLoanStage: loanStage,
              initialLoanIssueStatus: loanIssueStatus,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isWarning ? FontWeight.bold : FontWeight.w500,
                color: isWarning ? Colors.orange.shade800 : Colors.black87,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onTap;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _StatusCard({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
              ),
              Row(
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
