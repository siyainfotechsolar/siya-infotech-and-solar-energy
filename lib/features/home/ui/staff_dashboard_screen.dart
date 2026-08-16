import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../tasks/ui/incomplete_tasks_screen.dart';
import '../../more/ui/more_screen.dart';
import 'staff_home_screen.dart';
import 'exit_screen.dart';
import '../../tasks/providers/task_provider.dart';
import '../../tasks/providers/pending_task_count_provider.dart';
import '../../../core/services/permission_service.dart';

class StaffDashboardScreen extends ConsumerStatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  ConsumerState<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends ConsumerState<StaffDashboardScreen> {
  int _currentIndex = 0;

  Future<void> _handlePopScope(bool didPop) async {
    if (didPop) return;

    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
      return;
    }

    final count = await ref.read(pendingTaskCountProvider.future);
    if (mounted) {
      await ExitScreen.show(context, count);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incompleteAsync = ref.watch(incompleteTaskListProvider);
    final incompleteCount = incompleteAsync.value?.length ?? 0;
    final permsAsync = ref.watch(currentUserPermissionsProvider);

    return permsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => _buildDashboard(context, hasCustomerAccess: false, incompleteCount: incompleteCount),
      data: (perms) {
        final canViewCustomers = perms.canView(AppModule.customers);
        return _buildDashboard(context, hasCustomerAccess: canViewCustomers, incompleteCount: incompleteCount);
      },
    );
  }

  Widget _buildDashboard(
    BuildContext context, {
    required bool hasCustomerAccess,
    required int incompleteCount,
  }) {
    final List<Widget> pages = [
      const StaffHomeScreen(),
      if (hasCustomerAccess) const CustomerListScreen(),
      const TaskListScreen(),
      const IncompleteTasksScreen(),
      const MoreScreen(),
    ];

    if (_currentIndex >= pages.length) {
      _currentIndex = 0;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _handlePopScope(didPop),
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: pages),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            if (hasCustomerAccess)
              const BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: 'Customers',
              ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.task_alt),
              label: 'Tasks',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                label: Text('$incompleteCount'),
                isLabelVisible: incompleteCount > 0,
                child: const Icon(Icons.warning_amber_outlined),
              ),
              activeIcon: Badge(
                label: Text('$incompleteCount'),
                isLabelVisible: incompleteCount > 0,
                child: const Icon(Icons.warning_amber),
              ),
              label: 'Incomplete',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.menu),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
