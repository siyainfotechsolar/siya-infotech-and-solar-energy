import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../../core/notifications/notification_state.dart';
import '../../notifications/ui/notifications_screen.dart';
import '../../../core/widgets/app_tap_widgets.dart';
import '../../../core/services/permission_service.dart';

// Provider for staff dashboard stats
final staffDashboardStatsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return {
      'my_tasks': 0,
      'my_customers': 0,
      'pending_tasks': 0,
      'completed_tasks': 0,
      'attention_customers': 0,
      'priority_customers': 0,
      'critical_customers': 0,
    };
  }

  // Fetch task IDs assigned to the logged-in staff member
  final assignedRes = await supabase
      .from('task_staff')
      .select('task_id')
      .eq('staff_id', user.id);
      
  final taskIds = List<String>.from((assignedRes as List).map((e) => e['task_id'] as String));
  if (taskIds.isEmpty) {
    return {
      'my_tasks': 0,
      'my_customers': 0,
      'pending_tasks': 0,
      'completed_tasks': 0,
      'attention_customers': 0,
      'priority_customers': 0,
      'critical_customers': 0,
    };
  }

  // Fetch status & customer_id for those tasks
  final tasksResponse = await supabase
      .from('tasks')
      .select('status, customer_id')
      .inFilter('id', taskIds);

  final tasks = List<Map<String, dynamic>>.from(tasksResponse);
  final pending = tasks.where((t) => t['status'] != 'completed').length;
  final completed = tasks.where((t) => t['status'] == 'completed').length;
  final uniqueCustomerIds = tasks.map((t) => t['customer_id'] as String?).whereType<String>().toSet().toList();

  final now = DateTime.now();
  final d8 = now.subtract(const Duration(days: 8)).toIso8601String().split('T').first;
  final d14 = now.subtract(const Duration(days: 14)).toIso8601String().split('T').first;
  final d15 = now.subtract(const Duration(days: 15)).toIso8601String().split('T').first;
  final d29 = now.subtract(const Duration(days: 29)).toIso8601String().split('T').first;
  final d30 = now.subtract(const Duration(days: 30)).toIso8601String().split('T').first;

  int attention = 0;
  int priority = 0;
  int critical = 0;

  if (uniqueCustomerIds.isNotEmpty) {
    final attentionRes = await supabase
        .from('customers')
        .select('id')
        .inFilter('id', uniqueCustomerIds)
        .lte('application_date', d8)
        .gte('application_date', d14);
        
    final priorityRes = await supabase
        .from('customers')
        .select('id')
        .inFilter('id', uniqueCustomerIds)
        .lte('application_date', d15)
        .gte('application_date', d29);
        
    final criticalRes = await supabase
        .from('customers')
        .select('id')
        .inFilter('id', uniqueCustomerIds)
        .lte('application_date', d30);

    attention = (attentionRes as List).length;
    priority = (priorityRes as List).length;
    critical = (criticalRes as List).length;
  }

  return {
    'my_tasks': tasks.length,
    'my_customers': uniqueCustomerIds.length,
    'pending_tasks': pending,
    'completed_tasks': completed,
    'attention_customers': attention,
    'priority_customers': priority,
    'critical_customers': critical,
  };
});

class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(staffDashboardStatsProvider);
    final user = ref.watch(currentUserProvider);

    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solar CRM', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          _StaffNotificationBell(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(staffDashboardStatsProvider),
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading dashboard: $e')),
        data: (stats) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                    ref.watch(currentStaffProfileProvider).when(
                      loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (profile) {
                    final name = profile?['name'] ?? 'Staff';
                    final photoUrl = profile?['profile_photo_url'] as String?;
                    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
                    final theme = Theme.of(context);
                    
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withOpacity(0.85),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                              backgroundColor: hasPhoto ? Colors.transparent : Colors.white24,
                              child: hasPhoto ? null : Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$greeting,',
                                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    name,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user?.email ?? '',
                                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                const Text(
                  'OPERATIONS OVERVIEW',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),

                // Grid of Dashboard Stats Cards
                Builder(
                  builder: (context) {
                    final theme = Theme.of(context);
                    final permsAsync = ref.watch(currentUserPermissionsProvider);
                    final canViewCustomers = permsAsync.value?.canView(AppModule.customers) ?? false;

                    if (!canViewCustomers) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _DashboardCard(
                                  title: 'MY TASKS',
                                  count: stats['my_tasks'] ?? 0,
                                  icon: Icons.assignment_outlined,
                                  color: theme.colorScheme.primary,
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _DashboardCard(
                                  title: 'PENDING TASKS',
                                  count: stats['pending_tasks'] ?? 0,
                                  icon: Icons.hourglass_empty_outlined,
                                  color: Colors.orange,
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _DashboardCard(
                                  title: 'COMPLETED TASKS',
                                  count: stats['completed_tasks'] ?? 0,
                                  icon: Icons.task_alt_outlined,
                                  color: Colors.green,
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 1))),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: SizedBox.shrink()),
                            ],
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DashboardCard(
                                title: 'MY TASKS',
                                count: stats['my_tasks'] ?? 0,
                                icon: Icons.assignment_outlined,
                                color: theme.colorScheme.primary,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DashboardCard(
                                title: 'MY CUSTOMERS',
                                count: stats['my_customers'] ?? 0,
                                icon: Icons.people_outline,
                                color: theme.colorScheme.secondary,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen())),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DashboardCard(
                                title: 'PENDING TASKS',
                                count: stats['pending_tasks'] ?? 0,
                                icon: Icons.hourglass_empty_outlined,
                                color: Colors.orange,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DashboardCard(
                                title: 'COMPLETED TASKS',
                                count: stats['completed_tasks'] ?? 0,
                                icon: Icons.task_alt_outlined,
                                color: Colors.green,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 1))),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final permsAsync = ref.watch(currentUserPermissionsProvider);
                    final canViewCustomers = permsAsync.value?.canView(AppModule.customers) ?? false;
                    if (!canViewCustomers) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        const Text(
                          'CUSTOMER AGE OVERVIEW',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DashboardCard(
                                title: 'ATTENTION (8-14 DAYS)',
                                count: stats['attention_customers'] ?? 0,
                                icon: Icons.error_outline,
                                color: Colors.orange,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '8–14'))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DashboardCard(
                                title: 'PRIORITY (15-29 DAYS)',
                                count: stats['priority_customers'] ?? 0,
                                icon: Icons.priority_high,
                                color: Colors.deepOrange,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '15–29'))),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DashboardCard(
                                title: 'CRITICAL (30+ DAYS)',
                                count: stats['critical_customers'] ?? 0,
                                icon: Icons.dangerous,
                                color: Colors.red,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '30+'))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final debouncer = Debouncer();

    return Card(
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: InkWell(
        onTap: () {
          if (debouncer.canExecute()) {
            onTap();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.06),
                color.withValues(alpha: 0.01),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: color,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: color.withValues(alpha: 0.7)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─── Staff Notification Bell ──────────────────────────────────────────────
class _StaffNotificationBell extends ConsumerWidget {
  const _StaffNotificationBell();

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
