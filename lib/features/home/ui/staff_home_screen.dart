import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../staff/ui/delivery_details_screen.dart';
import '../../../core/notifications/notification_state.dart';
import '../../notifications/ui/notifications_screen.dart';

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

    final roleAsync = ref.watch(userRoleProvider);

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
      body: roleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (role) {
          return statsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading dashboard: $e')),
            data: (stats) {
              if (role == 'installer') {
                return ref.watch(currentStaffProfileProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => _buildInstallerDashboard(context, stats, null, user?.email),
                  data: (profile) => _buildInstallerDashboard(context, stats, profile, user?.email),
                );
              }

              if (role == 'delivery_staff') {
                if (user?.id == null) {
                  return const Center(child: Text('User ID is null'));
                }
                return ref.watch(currentStaffProfileProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => _DeliveryStaffDashboardWidget(profile: null, userId: user!.id),
                  data: (profile) => _DeliveryStaffDashboardWidget(profile: profile, userId: user!.id),
                );
              }

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

                // Grid of 4 Dashboard Stats Cards
                Builder(
                  builder: (context) {
                    final theme = Theme.of(context);
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
                const SizedBox(height: 24),

                const Text(
                  'CUSTOMER AGE OVERVIEW',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),

                // Grid of 3 Customer Age Cards
                Builder(
                  builder: (context) {
                    return Column(
                      children: [
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
      );
    },
  ),
);
}

  Widget _buildInstallerDashboard(
    BuildContext context,
    Map<String, int> stats,
    Map<String, dynamic>? profile,
    String? email,
  ) {
    final theme = Theme.of(context);
    final name = (profile?['name'] ?? 'Installer').toString().toUpperCase();
    final photoUrl = profile?['profile_photo_url'] as String?;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    final hour = DateTime.now().hour;
    final greeting = (hour < 12 ? 'GOOD MORNING' : hour < 17 ? 'GOOD AFTERNOON' : 'GOOD EVENING');

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Greeting & Profile Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting,',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.primary, letterSpacing: -0.5),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 26,
                backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: hasPhoto ? null : Text(
                  name.isNotEmpty ? name[0] : 'I',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // MY WORK SECTION
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'MY WORK',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.blueGrey, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: Colors.grey.shade300, thickness: 1.5),
                  const SizedBox(height: 12),
                  
                  // Assigned Tasks Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Assigned Tasks',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${stats['my_tasks'] ?? 0}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // Pending Sub-Row
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Pending',
                              style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        Text(
                          '${stats['pending_tasks'] ?? 0}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Completed Sub-Row
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Completed',
                              style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        Text(
                          '${stats['completed_tasks'] ?? 0}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.grey.shade200, thickness: 1),
                  const SizedBox(height: 12),

                  // Assigned Sites Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Assigned Sites',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${stats['my_customers'] ?? 0}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.secondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ACTIONS SECTION BUTTONS
          ElevatedButton.icon(
            icon: const Icon(Icons.assignment, size: 20),
            label: const Text('MY TASKS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen(initialIndex: 0))),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.location_on, size: 20),
            label: const Text('MY SITES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen())),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
          ),
        ],
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
    return Card(
      elevation: 2,
      shadowColor: color.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.2), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.06),
                color.withOpacity(0.01),
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
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryStaffDashboardWidget extends ConsumerStatefulWidget {
  final Map<String, dynamic>? profile;
  final String userId;

  const _DeliveryStaffDashboardWidget({
    required this.profile,
    required this.userId,
  });

  @override
  ConsumerState<_DeliveryStaffDashboardWidget> createState() => _DeliveryStaffDashboardWidgetState();
}

class _DeliveryStaffDashboardWidgetState extends ConsumerState<_DeliveryStaffDashboardWidget> {
  int _refreshCounter = 0;

  void _triggerRefresh() {
    setState(() {
      _refreshCounter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.profile?['name'] ?? 'Delivery Staff').toString().toUpperCase();
    final supabase = ref.watch(supabaseClientProvider);

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_refreshCounter),
      future: supabase
          .from('material_dispatches')
          .select('*, customers(name, village, pm_surya_ghar_application_id, address)')
          .eq('delivery_staff_id', widget.userId)
          .order('created_at', ascending: false)
          .then((res) => List<Map<String, dynamic>>.from(res)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading deliveries: ${snapshot.error}'));
        }

        final dispatches = snapshot.data ?? [];
        final pendingCount = dispatches.where((d) => d['status'] == 'Pending').length;
        final outCount = dispatches.where((d) => d['status'] == 'Out for Delivery').length;
        final deliveredCount = dispatches.where((d) => d['status'] == 'Delivered').length;

        return RefreshIndicator(
          onRefresh: () async {
            _triggerRefresh();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Text(
                'GOOD MORNING, $name',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 16),
              
              // Title Section
              const Text(
                'MY DELIVERIES',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),

              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard('Pending', pendingCount, Colors.red),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard('Out for Delivery', outCount, Colors.orange),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard('Delivered', deliveredCount, Colors.green),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Dispatches List
              if (dispatches.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No assigned deliveries found', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ),
                )
              else
                ...dispatches.map((d) {
                  final customer = d['customers'] ?? {};
                  final custName = customer['name'] ?? 'N/A';
                  final village = customer['village'] ?? 'N/A';
                  final materialName = d['material_name'] ?? 'N/A';
                  final qty = d['quantity'] ?? 0;
                  final status = d['status'] ?? 'Pending';
                  
                  Color badgeColor = Colors.red;
                  String statusEmoji = '🔴';
                  if (status == 'Out for Delivery') {
                    badgeColor = Colors.orange;
                    statusEmoji = '🟡';
                  } else if (status == 'Delivered') {
                    badgeColor = Colors.green;
                    statusEmoji = '🟢';
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Customer: $custName',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$statusEmoji $status',
                                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Site: $village', style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text('Material: $materialName × $qty', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DeliveryDetailsScreen(dispatch: d),
                                  ),
                                ).then((_) => _triggerRefresh());
                              },
                              child: const Text('VIEW DELIVERY'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showNotificationsDialog(BuildContext context, WidgetRef ref, String? userId) async {
  if (userId == null) return;
  final supabase = ref.read(supabaseClientProvider);
  
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications, color: Colors.blue),
            SizedBox(width: 8),
            Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: supabase
                .from('notifications')
                .select()
                .eq('user_id', userId)
                .order('created_at', ascending: false)
                .then((res) => List<Map<String, dynamic>>.from(res)),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text('No notifications yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final notif = list[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(notif['title'] ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(notif['message'] ?? ''),
                    trailing: Text(
                      notif['created_at'] != null 
                          ? DateTime.parse(notif['created_at']).toLocal().toString().substring(11, 16)
                          : '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Mark all as read
              supabase.from('notifications').update({'is_read': true}).eq('user_id', userId);
              Navigator.pop(context);
            },
            child: const Text('CLOSE'),
          ),
        ],
      );
    },
  );
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
