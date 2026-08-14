import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../customers/ui/customer_list_screen.dart';
import '../../tasks/ui/task_list_screen.dart';
import '../../tasks/ui/incomplete_tasks_screen.dart';
import '../../more/ui/more_screen.dart';
import 'admin_home_screen.dart';
import '../../tasks/providers/task_provider.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    AdminHomeScreen(),
    CustomerListScreen(),
    TaskListScreen(),
    IncompleteTasksScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final incompleteAsync = ref.watch(incompleteTaskListProvider);
    final incompleteCount = incompleteAsync.value?.length ?? 0;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Customers'),
          const BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: 'Tasks'),
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
          const BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}
