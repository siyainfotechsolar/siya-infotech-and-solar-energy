import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_wrapper.dart';
import '../../features/tasks/ui/task_list_screen.dart';
import '../../features/tasks/ui/task_details_screen.dart';
import '../../features/tasks/ui/incomplete_tasks_screen.dart';
import '../../features/tasks/services/task_details_router.dart';
import '../../features/customers/ui/customer_list_screen.dart';
import '../../features/customers/ui/customer_details_screen.dart';
import '../../features/notifications/ui/notifications_screen.dart';
import '../../core/services/permission_service.dart';

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
          final task = state.extra as Map<String, dynamic>? ?? {'id': taskId};
          return Consumer(
            builder: (context, ref, child) {
              final permsAsync = ref.watch(currentUserPermissionsProvider);
              return permsAsync.when(
                data: (perms) => TaskDetailsRouter.getWidgetForRole(permissions: perms, task: task),
                loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
                error: (_, __) => TaskDetailsScreen(task: task),
              );
            },
          );
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
        builder: (context, state) {
          return Consumer(
            builder: (context, ref, child) {
              final permsAsync = ref.watch(currentUserPermissionsProvider);
              return permsAsync.when(
                data: (perms) {
                  if (!perms.canView(AppModule.customers)) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Access Denied')),
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lock_outline, size: 56, color: Colors.red),
                              const SizedBox(height: 16),
                              const Text(
                                "You don't have permission to access Customers.",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () => context.go('/'),
                                icon: const Icon(Icons.home),
                                label: const Text('Return to Home'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return const CustomerListScreen();
                },
                loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
                error: (_, __) => const CustomerListScreen(),
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/customers/:id',
        name: 'customer-details',
        builder: (context, state) {
          final customerId = state.pathParameters['id'] ?? '';
          final customer = state.extra as Map<String, dynamic>? ?? {'id': customerId};
          return Consumer(
            builder: (context, ref, child) {
              final permsAsync = ref.watch(currentUserPermissionsProvider);
              return permsAsync.when(
                data: (perms) {
                  if (!perms.canView(AppModule.customers)) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Access Denied')),
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lock_outline, size: 56, color: Colors.red),
                              const SizedBox(height: 16),
                              const Text(
                                "You don't have permission to access Customers.",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () => context.go('/'),
                                icon: const Icon(Icons.home),
                                label: const Text('Return to Home'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return CustomerDetailsScreen(customer: customer);
                },
                loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
                error: (_, __) => CustomerDetailsScreen(customer: customer),
              );
            },
          );
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
