import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/connectivity_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/customers/providers/customer_provider.dart';
import '../../features/tasks/providers/task_provider.dart';
import '../../features/leads/providers/lead_provider.dart';
import '../../features/materials/providers/material_provider.dart';
import '../../features/staff/ui/staff_list_screen.dart';
import '../../features/home/ui/admin_home_screen.dart';
import '../../features/home/ui/staff_home_screen.dart';

// Providers to track active details screens
class ActiveCustomerIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void update(String? id) => state = id;
}
final activeCustomerIdProvider = NotifierProvider<ActiveCustomerIdNotifier, String?>(ActiveCustomerIdNotifier.new);

class ActiveTaskIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void update(String? id) => state = id;
}
final activeTaskIdProvider = NotifierProvider<ActiveTaskIdNotifier, String?>(ActiveTaskIdNotifier.new);

// Provider for global connection status
class ConnectionStatusNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void update(bool value) => state = value;
}
final connectionStatusProvider = NotifierProvider<ConnectionStatusNotifier, bool>(ConnectionStatusNotifier.new);

class RealtimeService with WidgetsBindingObserver {
  final Ref ref;
  final SupabaseClient supabase;
  
  Timer? _connectivityTimer;
  RealtimeChannel? _channel;
  bool _wasDisconnected = false;

  RealtimeService(this.ref, this.supabase);

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _startConnectivityMonitoring();
    _subscribeToRealtime();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivityTimer?.cancel();
    _unsubscribeRealtime();
  }

  void _startConnectivityMonitoring() {
    _connectivityTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final isConnected = await AppConnectivity.isConnected();
      final currentStatus = ref.read(connectionStatusProvider);
      
      if (isConnected != currentStatus) {
        ref.read(connectionStatusProvider.notifier).update(isConnected);
        
        if (isConnected) {
          // Connection restored: perform controlled sync refresh
          if (_wasDisconnected) {
            _wasDisconnected = false;
            synchronizeAll();
            // Reconnect Supabase realtime socket if needed
            // ignore: invalid_use_of_internal_member
            supabase.realtime.connect();
          }
        } else {
          _wasDisconnected = true;
        }
      }
    });
  }

  void _subscribeToRealtime() {
    _unsubscribeRealtime();

    _channel = supabase.channel('public:all_changes');
    
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: '*',
      callback: (payload) {
        debugPrint('Realtime Event: table=${payload.table}, event=${payload.eventType}');
        final table = payload.table;
        final type = payload.eventType;
        final oldRecord = payload.oldRecord;
        final newRecord = payload.newRecord;

        switch (table) {
          case 'customers':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              ref.read(customerListProvider.notifier).upsertCustomer(newRecord['id']);
              final activeCustomerId = ref.read(activeCustomerIdProvider);
              if (activeCustomerId == newRecord['id']) {
                ref.invalidate(customerHistoryProvider(newRecord['id']));
                ref.invalidate(customerTasksProvider(newRecord['id']));
              }
            } else if (type == PostgresChangeEvent.delete) {
              ref.read(customerListProvider.notifier).removeCustomer(oldRecord['id']);
            }
            ref.invalidate(adminHomeMetricsProvider);
            break;

          case 'leads':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              ref.read(leadListProvider.notifier).upsertLead(newRecord['id']);
            } else if (type == PostgresChangeEvent.delete) {
              ref.read(leadListProvider.notifier).removeLead(oldRecord['id']);
            }
            ref.invalidate(adminHomeMetricsProvider);
            break;

          case 'tasks':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              ref.read(taskListProvider.notifier).upsertTask(newRecord['id']);
              final customerId = newRecord['customer_id'];
              if (customerId != null) {
                ref.invalidate(customerTasksProvider(customerId));
              }
              final activeTaskId = ref.read(activeTaskIdProvider);
              if (activeTaskId == newRecord['id']) {
                ref.invalidate(taskDetailsProvider(newRecord['id']));
              }
            } else if (type == PostgresChangeEvent.delete) {
              ref.read(taskListProvider.notifier).removeTask(oldRecord['id']);
              final customerId = oldRecord['customer_id'];
              if (customerId != null) {
                ref.invalidate(customerTasksProvider(customerId));
              }
            }
            ref.invalidate(adminHomeMetricsProvider);
            ref.invalidate(staffDashboardStatsProvider);
            ref.invalidate(incompleteTaskListProvider);
            break;

          case 'staff':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              ref.read(staffListProvider.notifier).upsertStaff(newRecord['id']);
              final currentUser = ref.read(currentUserProvider);
              if (currentUser != null && newRecord['id'] == currentUser.id) {
                ref.invalidate(userRoleProvider);
              }
            } else if (type == PostgresChangeEvent.delete) {
              ref.read(staffListProvider.notifier).removeStaff(oldRecord['id']);
            }
            ref.invalidate(adminHomeMetricsProvider);
            break;

          case 'task_staff':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              final taskId = newRecord['task_id'];
              ref.read(taskListProvider.notifier).upsertTask(taskId);
              ref.read(staffListProvider.notifier).upsertStaff(newRecord['staff_id']);
              final activeTaskId = ref.read(activeTaskIdProvider);
              if (activeTaskId == taskId) {
                ref.invalidate(taskDetailsProvider(taskId));
              }
            }
            ref.invalidate(staffDashboardStatsProvider);
            break;

          case 'stage_history':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              final customerId = newRecord['customer_id'];
              if (customerId != null) {
                ref.invalidate(customerHistoryProvider(customerId));
              }
            }
            break;

          case 'task_activity':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              final taskId = newRecord['task_id'];
              if (taskId != null) {
                final activeTaskId = ref.read(activeTaskIdProvider);
                if (activeTaskId == taskId) {
                  ref.invalidate(taskDetailsProvider(taskId));
                }
              }
            }
            break;

          case 'site_installation_tasks':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              final customerId = newRecord['customer_id'];
              if (customerId != null) {
                ref.invalidate(installationTasksProvider(customerId));
                ref.read(customerListProvider.notifier).upsertCustomer(customerId);
              }
            }
            break;

          case 'site_materials':
            if (type == PostgresChangeEvent.insert || type == PostgresChangeEvent.update) {
              final siteId = newRecord['site_id'];
              if (siteId != null) {
                ref.invalidate(siteMaterialsProvider(siteId));
              }
            } else if (type == PostgresChangeEvent.delete) {
              final siteId = oldRecord['site_id'];
              if (siteId != null) {
                ref.invalidate(siteMaterialsProvider(siteId));
              }
            }
            break;
        }
      },
    ).subscribe();
  }

  void _unsubscribeRealtime() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  void synchronizeAll() {
    ref.invalidate(customerListProvider);
    ref.invalidate(leadListProvider);
    ref.invalidate(taskListProvider);
    ref.invalidate(staffListProvider);
    ref.invalidate(adminHomeMetricsProvider);
    ref.invalidate(staffDashboardStatsProvider);
    
    // Refresh active details screens if they are open
    final activeCustomerId = ref.read(activeCustomerIdProvider);
    if (activeCustomerId != null) {
      ref.invalidate(customerHistoryProvider(activeCustomerId));
      ref.invalidate(customerTasksProvider(activeCustomerId));
    }
    final activeTaskId = ref.read(activeTaskIdProvider);
    if (activeTaskId != null) {
      ref.invalidate(taskDetailsProvider(activeTaskId));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyAndReconnect();
    }
  }

  Future<void> _verifyAndReconnect() async {
    final isConnected = await AppConnectivity.isConnected();
    ref.read(connectionStatusProvider.notifier).update(isConnected);
    
    if (isConnected) {
      // ignore: invalid_use_of_internal_member
      supabase.realtime.connect();
      synchronizeAll();
    }
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final service = RealtimeService(ref, supabase);
  service.init();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
