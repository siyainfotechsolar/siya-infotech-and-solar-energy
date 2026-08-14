import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../customers/providers/customer_provider.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../leads/ui/lead_list_screen.dart';
import '../../../core/notifications/notification_state.dart';
import '../../notifications/ui/notifications_screen.dart';

class AdminKpiNotifier extends AsyncNotifier<Map<String, int>> {
  @override
  Future<Map<String, int>> build() async {
    return _fetchKpis();
  }

  Future<Map<String, int>> _fetchKpis() async {
    final supabase = ref.read(supabaseClientProvider);
    final now = DateTime.now();

    final d8 = now.subtract(const Duration(days: 8)).toIso8601String().split('T').first;
    final d14 = now.subtract(const Duration(days: 14)).toIso8601String().split('T').first;
    final d15 = now.subtract(const Duration(days: 15)).toIso8601String().split('T').first;
    final d29 = now.subtract(const Duration(days: 29)).toIso8601String().split('T').first;
    final d30 = now.subtract(const Duration(days: 30)).toIso8601String().split('T').first;

    final todayStart = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final customersRes = await supabase.from('customers').select('id');
    final pendingRes = await supabase.from('tasks').select('id').neq('status', 'completed');
    final todayRes = await supabase.from('tasks').select('id').gte('created_at', todayStart).neq('status', 'completed');
    final highPriorityRes = await supabase.from('tasks').select('id').eq('priority', 'high').neq('status', 'completed');
    final starredRes = await supabase.from('customers').select('id').eq('priority', true);
    final leadsRes = await supabase.from('leads').select('id').neq('status', 'converted');
    
    final attentionRes = await supabase.from('customers').select('id').lte('application_date', d8).gte('application_date', d14);
    final priorityRes = await supabase.from('customers').select('id').lte('application_date', d15).gte('application_date', d29);
    final criticalRes = await supabase.from('customers').select('id').lte('application_date', d30);

    return {
      'customers': (customersRes as List).length,
      'pending': (pendingRes as List).length,
      'today': (todayRes as List).length,
      'high_priority': (highPriorityRes as List).length,
      'starred': (starredRes as List).length,
      'leads': (leadsRes as List).length,
      'attention': (attentionRes as List).length,
      'priority': (priorityRes as List).length,
      'critical': (criticalRes as List).length,
    };
  }

  Future<void> refreshSilently() async {
    try {
      final kpis = await _fetchKpis();
      state = AsyncData(kpis);
    } catch (e) {
      // Ignored
    }
  }
}

final adminKpiProvider = AsyncNotifierProvider<AdminKpiNotifier, Map<String, int>>(AdminKpiNotifier.new);

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(adminKpiProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          _NotificationBell(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminKpiProvider),
          ),
        ],
      ),
      body: kpiAsync.when(
        data: (kpi) => _KpiGrid(kpi: kpi),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(adminKpiProvider)),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Could not load dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Check your internet connection', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends ConsumerWidget {
  final Map<String, int> kpi;
  const _KpiGrid({required this.kpi});

  void _navToCustomers(BuildContext context, WidgetRef ref, {bool priority = false, String? ageRange}) async {
    final previous = ref.read(customerFilterProvider);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerListScreen(filterPriority: priority, filterAgeRange: ageRange)));
    ref.read(customerFilterProvider.notifier).updateFilter(previous);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KpiCard(
            title: 'Total Customers',
            count: kpi['customers'] ?? 0,
            icon: Icons.people,
            color: Colors.blue,
            onTap: () => _navToCustomers(context, ref),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _KpiCard(
              title: 'Pending Tasks',
              count: kpi['pending'] ?? 0,
              icon: Icons.pending_actions,
              color: Colors.orange,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
            )),
            const SizedBox(width: 12),
            Expanded(child: _KpiCard(
              title: "Today's Tasks",
              count: kpi['today'] ?? 0,
              icon: Icons.today,
              color: Colors.green,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _KpiCard(
              title: 'High Priority',
              count: kpi['high_priority'] ?? 0,
              icon: Icons.warning_amber,
              color: Colors.red,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0, initialFilterPriority: 'high'))),
            )),
            const SizedBox(width: 12),
            Expanded(child: _KpiCard(
              title: 'Starred',
              count: kpi['starred'] ?? 0,
              icon: Icons.star,
              color: Colors.amber,
              onTap: () => _navToCustomers(context, ref, priority: true),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _KpiCard(
              title: 'Attention (8-14 Days)',
              count: kpi['attention'] ?? 0,
              icon: Icons.error_outline,
              color: Colors.orange,
              onTap: () => _navToCustomers(context, ref, ageRange: '8–14'),
            )),
            const SizedBox(width: 12),
            Expanded(child: _KpiCard(
              title: 'Priority (15-29 Days)',
              count: kpi['priority'] ?? 0,
              icon: Icons.priority_high,
              color: Colors.deepOrange,
              onTap: () => _navToCustomers(context, ref, ageRange: '15–29'),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _KpiCard(
              title: 'Critical (30+ Days)',
              count: kpi['critical'] ?? 0,
              icon: Icons.dangerous,
              color: Colors.red,
              onTap: () => _navToCustomers(context, ref, ageRange: '30+'),
            )),
            const SizedBox(width: 12),
            Expanded(child: _KpiCard(
              title: 'New Leads',
              count: kpi['leads'] ?? 0,
              icon: Icons.leaderboard,
              color: Colors.teal,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadListScreen())),
            )),
          ]),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _KpiCard({required this.title, required this.count, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 28),
                  if (onTap != null) Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 12),
              Text(count.toString(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Global Notification Bell ─────────────────────────────────────────────
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
