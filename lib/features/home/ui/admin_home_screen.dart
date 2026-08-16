import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../customers/ui/add_customer_screen.dart';
import '../../leads/ui/lead_list_screen.dart';
import '../../leads/ui/add_lead_screen.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../tasks/ui/add_task_screen.dart';
import '../../tasks/ui/incomplete_tasks_screen.dart';
import '../../staff/ui/staff_directory_screen.dart';
import '../../staff/ui/staff_list_screen.dart';
import '../../staff/ui/add_staff_screen.dart';
import '../../import/ui/import_screen.dart';
import '../../../core/notifications/notification_state.dart';
import '../../notifications/ui/notifications_screen.dart';

// ─── SECTION 1: CUSTOMER OVERVIEW PROVIDER ─────────────────────────────────
final adminCustomerOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final now = DateTime.now();
  final d7 = now.subtract(const Duration(days: 7)).toIso8601String().split('T').first;

  // Run in parallel
  final results = await Future.wait([
    supabase.from('customers').select('id'),
    supabase.from('customers').select('id').gte('application_date', d7),
  ]);

  return {
    'total': (results[0] as List).length,
    'new': (results[1] as List).length,
  };
});

// ─── SECTION 2: CUSTOMER AGE PROVIDER ──────────────────────────────────────
final adminCustomerAgeProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final now = DateTime.now();

  final d7  = now.subtract(const Duration(days: 7)).toIso8601String().split('T').first;
  final d8  = now.subtract(const Duration(days: 8)).toIso8601String().split('T').first;
  final d14 = now.subtract(const Duration(days: 14)).toIso8601String().split('T').first;
  final d15 = now.subtract(const Duration(days: 15)).toIso8601String().split('T').first;
  final d29 = now.subtract(const Duration(days: 29)).toIso8601String().split('T').first;
  final d30 = now.subtract(const Duration(days: 30)).toIso8601String().split('T').first;

  // All 4 age-bucket queries run in parallel
  final results = await Future.wait([
    supabase.from('customers').select('id').gte('application_date', d7),
    supabase.from('customers').select('id').lte('application_date', d8).gte('application_date', d14),
    supabase.from('customers').select('id').lte('application_date', d15).gte('application_date', d29),
    supabase.from('customers').select('id').lte('application_date', d30),
  ]);

  return {
    'd0to7':   (results[0] as List).length,
    'd8to14':  (results[1] as List).length,
    'd15to29': (results[2] as List).length,
    'd30plus': (results[3] as List).length,
  };
});

// ─── SECTION 3: LEAD OVERVIEW PROVIDER ─────────────────────────────────────
final adminLeadOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);

  // 5 lead queries run in parallel
  final results = await Future.wait([
    supabase.from('leads').select('id'),
    supabase.from('leads').select('id').inFilter('status', ['new', 'pending']),
    supabase.from('leads').select('id').inFilter('status', ['follow_up', 'followup', 'contacted']),
    supabase.from('leads').select('id').eq('status', 'converted'),
    supabase.from('leads').select('id').eq('status', 'lost'),
  ]);

  return {
    'total':    (results[0] as List).length,
    'new':      (results[1] as List).length,
    'followUp': (results[2] as List).length,
    'converted':(results[3] as List).length,
    'lost':     (results[4] as List).length,
  };
});

// ─── SECTION 4: TASK OVERVIEW PROVIDER ─────────────────────────────────────
final adminTaskOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);

  // 4 task status counts run in parallel
  final results = await Future.wait([
    supabase.from('tasks').select('id').ilike('status', 'pending'),
    supabase.from('tasks').select('id').ilike('status', 'in_progress'),
    supabase.from('tasks').select('id').ilike('status', 'not_completed'),
    supabase.from('tasks').select('id').ilike('status', 'completed'),
  ]);

  return {
    'pending':    (results[0] as List).length,
    'inProgress': (results[1] as List).length,
    'incomplete': (results[2] as List).length,
    'completed':  (results[3] as List).length,
  };
});

// ─── SECTION 5: INSTALLATION OVERVIEW PROVIDER ────────────────────────────
final adminInstallationOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);

  // 4 stage counts run in parallel
  final results = await Future.wait([
    supabase.from('customers').select('id').eq('stage', 'Installation'),
    supabase.from('customers').select('id').eq('stage', 'RTS'),
    supabase.from('customers').select('id').eq('stage', 'Subsidy'),
    supabase.from('customers').select('id').eq('stage', 'Completed'),
  ]);

  return {
    'installationPending': (results[0] as List).length,
    'rtsPending':          (results[1] as List).length,
    'subsidyPending':      (results[2] as List).length,
    'completed':           (results[3] as List).length,
  };
});

// ─── SECTION 6: STAFF OVERVIEW PROVIDER ───────────────────────────────────
final adminStaffOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);

  // Staff counts + task-staff joins run in parallel
  final results = await Future.wait([
    supabase.from('staff').select('id'),
    supabase.from('staff').select('id').eq('status', 'active'),
    supabase.from('task_staff').select('staff_id, tasks!inner(status)').inFilter('tasks.status', ['pending', 'in_progress']),
    supabase.from('task_staff').select('staff_id, tasks!inner(status)').eq('tasks.status', 'not_completed'),
  ]);

  final pendingStaffSet = (results[2] as List).map((e) => e['staff_id']).toSet();
  final incompleteStaffSet = (results[3] as List).map((e) => e['staff_id']).toSet();

  return {
    'total':          (results[0] as List).length,
    'active':         (results[1] as List).length,
    'withPending':    pendingStaffSet.length,
    'withIncomplete': incompleteStaffSet.length,
  };
});

// ─── MAIN ADMIN HOME SCREEN ────────────────────────────────────────────────
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(adminCustomerOverviewProvider);
    ref.invalidate(adminCustomerAgeProvider);
    ref.invalidate(adminLeadOverviewProvider);
    ref.invalidate(adminTaskOverviewProvider);
    ref.invalidate(adminInstallationOverviewProvider);
    ref.invalidate(adminStaffOverviewProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          const _NotificationBell(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshAll(ref),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 2. ADMIN WELCOME
            const _AdminWelcomeSection(),
            const SizedBox(height: 20),

            // 3. CUSTOMER OVERVIEW
            const _SectionHeader(title: 'CUSTOMERS'),
            const SizedBox(height: 8),
            const _CustomerOverviewSection(),
            const SizedBox(height: 20),

            // 4. CUSTOMER AGE
            const _SectionHeader(title: 'CUSTOMER AGE'),
            const SizedBox(height: 8),
            const _CustomerAgeSection(),
            const SizedBox(height: 20),

            // 5. LEAD OVERVIEW
            const _SectionHeader(title: 'LEADS'),
            const SizedBox(height: 8),
            const _LeadOverviewSection(),
            const SizedBox(height: 20),

            // 6. TASK OVERVIEW
            const _SectionHeader(title: 'TASKS'),
            const SizedBox(height: 8),
            const _TaskOverviewSection(),
            const SizedBox(height: 20),

            // 7. INSTALLATION OVERVIEW
            const _SectionHeader(title: 'INSTALLATION'),
            const SizedBox(height: 8),
            const _InstallationOverviewSection(),
            const SizedBox(height: 20),

            // 8. STAFF OVERVIEW
            const _SectionHeader(title: 'STAFF'),
            const SizedBox(height: 8),
            const _StaffOverviewSection(),
            const SizedBox(height: 20),

            // 9. IMPORTANT / ATTENTION
            const _SectionHeader(title: 'IMPORTANT'),
            const SizedBox(height: 8),
            const _ImportantAlertsSection(),
            const SizedBox(height: 20),

            // 10. QUICK ACTIONS
            const _SectionHeader(title: 'QUICK ACTIONS'),
            const SizedBox(height: 12),
            const _QuickActionsSection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── 2. ADMIN WELCOME SECTION ───────────────────────────────────────────────
class _AdminWelcomeSection extends ConsumerWidget {
  const _AdminWelcomeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentStaffProfileProvider);
    final adminName = profileAsync.when(
      data: (p) => (p?['name'] as String?)?.isNotEmpty == true ? p!['name'] : 'Admin',
      loading: () => 'Admin',
      error: (e, _) => 'Admin',
    );

    String greeting() {
      final hour = DateTime.now().hour;
      if (hour < 12) return 'Good Morning';
      if (hour < 17) return 'Good Afternoon';
      return 'Good Evening';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor,
            child: const Icon(Icons.security, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${greeting()}, $adminName',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              const Text(
                'Administrator',
                style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 3. CUSTOMER OVERVIEW WIDGET ───────────────────────────────────────────
class _CustomerOverviewSection extends ConsumerWidget {
  const _CustomerOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminCustomerOverviewProvider);

    return asyncData.when(
      data: (data) => Row(
        children: [
          Expanded(
            child: _KpiCard(
              title: 'TOTAL CUSTOMERS',
              count: data['total'] ?? 0,
              icon: Icons.people_alt_outlined,
              color: Colors.blue,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen())),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              title: 'NEW CUSTOMERS',
              count: data['new'] ?? 0,
              icon: Icons.person_add_outlined,
              color: Colors.blue,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '0–7'))),
            ),
          ),
        ],
      ),
      loading: () => const _SectionSkeleton(height: 90),
      error: (e, _) => _SectionErrorTile(onRetry: () => ref.invalidate(adminCustomerOverviewProvider)),
    );
  }
}

// ─── 4. CUSTOMER AGE WIDGET ────────────────────────────────────────────────
class _CustomerAgeSection extends ConsumerWidget {
  const _CustomerAgeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminCustomerAgeProvider);

    return asyncData.when(
      data: (data) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'NEW (0–7 DAYS)',
                  count: data['d0to7'] ?? 0,
                  icon: Icons.new_releases_outlined,
                  color: Colors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '0–7'))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'ATTENTION (8–14 DAYS)',
                  count: data['d8to14'] ?? 0,
                  icon: Icons.error_outline,
                  color: Colors.amber.shade800,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '8–14'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'PRIORITY (15–29 DAYS)',
                  count: data['d15to29'] ?? 0,
                  icon: Icons.priority_high,
                  color: Colors.deepOrange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '15–29'))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'OVERDUE (30+ DAYS)',
                  count: data['d30plus'] ?? 0,
                  icon: Icons.dangerous_outlined,
                  color: Colors.red,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '30+'))),
                ),
              ),
            ],
          ),
        ],
      ),
      loading: () => const _SectionSkeleton(height: 190),
      error: (e, _) => _SectionErrorTile(onRetry: () => ref.invalidate(adminCustomerAgeProvider)),
    );
  }
}

// ─── 5. LEAD OVERVIEW WIDGET ───────────────────────────────────────────────
class _LeadOverviewSection extends ConsumerWidget {
  const _LeadOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminLeadOverviewProvider);

    return asyncData.when(
      data: (data) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'TOTAL LEADS',
                  count: data['total'] ?? 0,
                  icon: Icons.leaderboard_outlined,
                  color: Colors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadListScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'NEW LEADS',
                  count: data['new'] ?? 0,
                  icon: Icons.add_circle_outline,
                  color: Colors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadListScreen(filterStatus: 'new'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'FOLLOW-UP',
                  count: data['followUp'] ?? 0,
                  icon: Icons.phone_callback_outlined,
                  color: Colors.amber.shade800,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadListScreen(filterStatus: 'follow_up'))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'CONVERTED',
                  count: data['converted'] ?? 0,
                  icon: Icons.task_alt_outlined,
                  color: Colors.green,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadListScreen(filterStatus: 'converted'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _KpiCard(
            title: 'LOST',
            count: data['lost'] ?? 0,
            icon: Icons.cancel_outlined,
            color: Colors.red,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeadListScreen(filterStatus: 'lost'))),
          ),
        ],
      ),
      loading: () => const _SectionSkeleton(height: 270),
      error: (e, _) => _SectionErrorTile(onRetry: () => ref.invalidate(adminLeadOverviewProvider)),
    );
  }
}

// ─── 6. TASK OVERVIEW WIDGET ───────────────────────────────────────────────
class _TaskOverviewSection extends ConsumerWidget {
  const _TaskOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminTaskOverviewProvider);

    return asyncData.when(
      data: (data) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'PENDING',
                  count: data['pending'] ?? 0,
                  icon: Icons.pending_actions_outlined,
                  color: Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'IN PROGRESS',
                  count: data['inProgress'] ?? 0,
                  icon: Icons.autorenew_outlined,
                  color: Colors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'INCOMPLETE',
                  count: data['incomplete'] ?? 0,
                  icon: Icons.warning_amber_outlined,
                  color: Colors.red,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncompleteTasksScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'COMPLETED',
                  count: data['completed'] ?? 0,
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 1))),
                ),
              ),
            ],
          ),
        ],
      ),
      loading: () => const _SectionSkeleton(height: 190),
      error: (e, _) => _SectionErrorTile(onRetry: () => ref.invalidate(adminTaskOverviewProvider)),
    );
  }
}

// ─── 7. INSTALLATION OVERVIEW WIDGET ───────────────────────────────────────
class _InstallationOverviewSection extends ConsumerWidget {
  const _InstallationOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminInstallationOverviewProvider);

    return asyncData.when(
      data: (data) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'INSTALLATION PENDING',
                  count: data['installationPending'] ?? 0,
                  icon: Icons.build_outlined,
                  color: Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['Installation']))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'RTS PENDING',
                  count: data['rtsPending'] ?? 0,
                  icon: Icons.assignment_outlined,
                  color: Colors.teal,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['RTS']))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'SUBSIDY PENDING',
                  count: data['subsidyPending'] ?? 0,
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.amber.shade800,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['Subsidy']))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'COMPLETED',
                  count: data['completed'] ?? 0,
                  icon: Icons.verified_outlined,
                  color: Colors.green,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['Completed']))),
                ),
              ),
            ],
          ),
        ],
      ),
      loading: () => const _SectionSkeleton(height: 190),
      error: (e, _) => _SectionErrorTile(onRetry: () => ref.invalidate(adminInstallationOverviewProvider)),
    );
  }
}

// ─── 8. STAFF OVERVIEW WIDGET ──────────────────────────────────────────────
class _StaffOverviewSection extends ConsumerWidget {
  const _StaffOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(adminStaffOverviewProvider);

    return asyncData.when(
      data: (data) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'TOTAL STAFF',
                  count: data['total'] ?? 0,
                  icon: Icons.badge_outlined,
                  color: Colors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffDirectoryScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'ACTIVE STAFF',
                  count: data['active'] ?? 0,
                  icon: Icons.check_circle_outline,
                  color: Colors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffDirectoryScreen())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'STAFF W/ PENDING TASKS',
                  count: data['withPending'] ?? 0,
                  icon: Icons.pending_outlined,
                  color: Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffListScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'STAFF W/ INCOMPLETE TASKS',
                  count: data['withIncomplete'] ?? 0,
                  icon: Icons.report_problem_outlined,
                  color: Colors.red,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncompleteTasksScreen())),
                ),
              ),
            ],
          ),
        ],
      ),
      loading: () => const _SectionSkeleton(height: 190),
      error: (e, _) => _SectionErrorTile(onRetry: () => ref.invalidate(adminStaffOverviewProvider)),
    );
  }
}

// ─── 9. IMPORTANT / ATTENTION SECTION WIDGET ────────────────────────────────
class _ImportantAlertsSection extends ConsumerWidget {
  const _ImportantAlertsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskData = ref.watch(adminTaskOverviewProvider).value;
    final ageData = ref.watch(adminCustomerAgeProvider).value;
    final instData = ref.watch(adminInstallationOverviewProvider).value;

    final incompleteCount = taskData?['incomplete'] ?? 0;
    final followUpCount = (ageData?['d8to14'] ?? 0) + (ageData?['d15to29'] ?? 0) + (ageData?['d30plus'] ?? 0);
    final instPendingCount = instData?['installationPending'] ?? 0;
    final rtsPendingCount = instData?['rtsPending'] ?? 0;
    final subsidyPendingCount = instData?['subsidyPending'] ?? 0;

    final alerts = <Widget>[];

    if (incompleteCount > 0) {
      alerts.add(_AlertTile(
        title: 'Incomplete Tasks',
        count: incompleteCount,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncompleteTasksScreen())),
      ));
    }

    if (followUpCount > 0) {
      alerts.add(_AlertTile(
        title: 'Customer Follow-up',
        count: followUpCount,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterAgeRange: '8–14'))),
      ));
    }

    if (instPendingCount > 0) {
      alerts.add(_AlertTile(
        title: 'Installation Pending',
        count: instPendingCount,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['Installation']))),
      ));
    }

    if (rtsPendingCount > 0) {
      alerts.add(_AlertTile(
        title: 'RTS Pending',
        count: rtsPendingCount,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['RTS']))),
      ));
    }

    if (subsidyPendingCount > 0) {
      alerts.add(_AlertTile(
        title: 'Subsidy Pending',
        count: subsidyPendingCount,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['Subsidy']))),
      ));
    }

    if (alerts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 12),
            Text('All business items up to date!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Column(children: alerts);
  }
}

class _AlertTile extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onTap;

  const _AlertTile({
    required this.title,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      color: Colors.amber.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 10. QUICK ACTIONS WIDGET ──────────────────────────────────────────────
class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                label: '+ CUSTOMER',
                icon: Icons.person_add_outlined,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerScreen())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionButton(
                label: '+ LEAD',
                icon: Icons.leaderboard_outlined,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddLeadScreen())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                label: '+ TASK',
                icon: Icons.add_task_outlined,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddTaskScreen())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionButton(
                label: '+ STAFF',
                icon: Icons.person_add_alt_1_outlined,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddStaffScreen())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                label: 'DISPATCH',
                icon: Icons.local_shipping_outlined,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen(filterStages: ['Installation']))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionButton(
                label: 'IMPORT',
                icon: Icons.file_upload_outlined,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── COMMON DASHBOARD UI COMPONENTS ───────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.6,
        color: Colors.black87,
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _KpiCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 24),
                  Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                count.toString(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.1),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  final double height;
  const _SectionSkeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _SectionErrorTile extends StatelessWidget {
  final VoidCallback onRetry;
  const _SectionErrorTile({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Unable to load section', style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('RETRY', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
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
