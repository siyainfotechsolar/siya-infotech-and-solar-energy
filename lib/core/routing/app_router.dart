import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_wrapper.dart';
import '../../features/tasks/ui/task_list_screen.dart';
import '../../features/tasks/ui/task_details_screen.dart';
import '../../features/tasks/ui/incomplete_tasks_screen.dart';
import '../../features/customers/ui/customer_list_screen.dart';
import '../../features/customers/ui/customer_details_screen.dart';
import '../../features/notifications/ui/notifications_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      // ── Root / Auth entry point ─────────────────────────────────
      GoRoute(
        path: '/',
        builder: (context, state) => const AuthWrapper(),
      ),

      // ── Tasks ───────────────────────────────────────────────────
      GoRoute(
        path: '/tasks',
        name: 'tasks',
        builder: (context, state) => const TaskListScreen(),
      ),
      GoRoute(
        path: '/tasks/:id',
        name: 'task-details',
        builder: (context, state) {
          final taskId = state.pathParameters['id'] ?? '';
          // Task map is passed via extra for in-app nav; deep link shows loading
          final task = state.extra as Map<String, dynamic>? ?? {'id': taskId};
          return TaskDetailsScreen(task: task);
        },
      ),
      GoRoute(
        path: '/tasks/incomplete',
        name: 'incomplete-tasks',
        builder: (context, state) => const IncompleteTasksScreen(),
      ),

      // ── Customers ───────────────────────────────────────────────
      GoRoute(
        path: '/customers',
        name: 'customers',
        builder: (context, state) => const CustomerListScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        name: 'customer-details',
        builder: (context, state) {
          final customerId = state.pathParameters['id'] ?? '';
          final customer = state.extra as Map<String, dynamic>? ?? {'id': customerId};
          return CustomerDetailsScreen(customer: customer);
        },
      ),

      // ── Notifications ───────────────────────────────────────────
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
    ],
  );
});

