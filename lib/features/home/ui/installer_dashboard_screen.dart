import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../tasks/ui/incomplete_tasks_screen.dart';
import '../../tasks/providers/task_provider.dart';
import '../../tasks/providers/pending_task_count_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/notifications/notification_state.dart';
import '../../notifications/ui/notifications_screen.dart';
import 'exit_screen.dart';

class InstallerDashboardScreen extends ConsumerStatefulWidget {
  const InstallerDashboardScreen({super.key});

  @override
  ConsumerState<InstallerDashboardScreen> createState() => _InstallerDashboardScreenState();
}

class _InstallerDashboardScreenState extends ConsumerState<InstallerDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    _InstallerHomeTab(),
    TaskListScreen(),
    IncompleteTasksScreen(),
  ];

  Future<void> _handlePopScope(bool didPop) async {
    if (didPop) return;
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }
    final count = await ref.read(pendingTaskCountProvider.future);
    if (mounted) await ExitScreen.show(context, count);
  }

  @override
  Widget build(BuildContext context) {
    final incompleteAsync = ref.watch(incompleteTaskListProvider);
    final incompleteCount = incompleteAsync.value?.length ?? 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _handlePopScope(didPop),
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _pages),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
            const BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: 'My Tasks'),
            BottomNavigationBarItem(
              icon: Badge(label: Text('$incompleteCount'), isLabelVisible: incompleteCount > 0, child: const Icon(Icons.warning_amber_outlined)),
              activeIcon: Badge(label: Text('$incompleteCount'), isLabelVisible: incompleteCount > 0, child: const Icon(Icons.warning_amber)),
              label: 'Incomplete',
            ),
          ],
        ),
      ),
    );
  }
}

// -- Installer Home Tab ------------------------------------------------------
class _InstallerHomeTab extends ConsumerWidget {
  const _InstallerHomeTab();

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentStaffProfileProvider);
    final tasksAsync = ref.watch(taskListProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    final name = profileAsync.when(
      data: (p) => (p?['name'] as String?)?.isNotEmpty == true ? p!['name'] : 'Installer',
      loading: () => 'Installer',
      error: (_, __) => 'Installer',
    );
    final pendingCount = tasksAsync.when(
      data: (tasks) => tasks.where((t) => t['status'] != 'completed').length,
      loading: () => 0, error: (_, __) => 0,
    );
    final completedCount = tasksAsync.when(
      data: (tasks) => tasks.where((t) => t['status'] == 'completed').length,
      loading: () => 0, error: (_, __) => 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Stack(children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(children: [
                CircleAvatar(backgroundColor: Theme.of(context).primaryColor, child: const Icon(Icons.engineering, color: Colors.white)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_greeting()}, $name', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Text('Field Installer', style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('MY TASKS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _StatCard(label: 'PENDING', count: pendingCount, icon: Icons.pending_actions_outlined, color: Colors.orange)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'COMPLETED', count: completedCount, icon: Icons.check_circle_outline, color: Colors.green)),
            ]),
            const SizedBox(height: 20),
            const Text('QUICK ACTIONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskListScreen())),
              icon: const Icon(Icons.task_alt),
              label: const Text('VIEW ALL MY TASKS'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.count, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8)),
      ]),
    );
  }
}
