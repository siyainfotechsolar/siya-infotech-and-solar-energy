import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/date_utils.dart';

class CustomerFilter {
  final String query;
  final List<String> stages;
  final String? village;
  final String? ageRange;
  final bool? priority;
  final String? loan;
  final String? installation;

  CustomerFilter({
    this.query = '',
    this.stages = const [],
    this.village,
    this.ageRange,
    this.priority,
    this.loan = 'All',
    this.installation = 'All',
  });

  CustomerFilter copyWith({
    String? query,
    List<String>? stages,
    String? village,
    String? ageRange,
    bool? priority,
    String? loan,
    String? installation,
  }) {
    return CustomerFilter(
      query: query ?? this.query,
      stages: stages ?? this.stages,
      village: village ?? this.village,
      ageRange: ageRange ?? this.ageRange,
      priority: priority ?? this.priority,
      loan: loan ?? this.loan,
      installation: installation ?? this.installation,
    );
  }
}

class CustomerFilterNotifier extends Notifier<CustomerFilter> {
  @override
  CustomerFilter build() => CustomerFilter();

  void updateFilter(CustomerFilter filter) {
    state = filter;
  }
}

final customerFilterProvider = NotifierProvider<CustomerFilterNotifier, CustomerFilter>(CustomerFilterNotifier.new);

class CustomerListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  int _page = 0;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    _page = 0;
    _hasMore = true;
    _isLoadingMore = false;
    return _fetchPage(0);
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int page) async {
    final supabase = ref.watch(supabaseClientProvider);
    final filter = ref.watch(customerFilterProvider);
    final user = ref.read(currentUserProvider);
    final role = await ref.read(userRoleProvider.future);

    List<String> installerCustomerIds = [];
    if (role == 'installer' && user != null) {
      final assignedRes = await supabase
          .from('task_staff')
          .select('tasks(customer_id)')
          .eq('staff_id', user.id);
      
      installerCustomerIds = (assignedRes as List)
          .map((item) => (item['tasks'] as Map?)?['customer_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      if (installerCustomerIds.isEmpty) {
        _hasMore = false;
        return [];
      }
    }

    var query = supabase
        .from('customers')
        .select('*, site_installation_tasks(task_type, status)');

    if (role == 'installer') {
      query = query.inFilter('id', installerCustomerIds);
    }

    if (filter.query.isNotEmpty) {
      query = query.or('name.ilike.%${filter.query}%,mobile.ilike.%${filter.query}%,consumer_number.ilike.%${filter.query}%,customer_id.ilike.%${filter.query}%,village.ilike.%${filter.query}%,pm_surya_ghar_application_id.ilike.%${filter.query}%');
    }

    if (filter.stages.isNotEmpty) {
      query = query.inFilter('stage', filter.stages);
    }

    if (filter.village != null && filter.village!.isNotEmpty) {
      query = query.eq('village', filter.village!);
    }

    if (filter.loan != null && filter.loan != 'All') {
      query = query.eq('loan_required', filter.loan == 'Yes');
    }

    if (filter.installation != null && filter.installation != 'All') {
      query = query.eq('stage', 'Installation');
    }

    if (filter.priority == true) {
      query = query.eq('priority', true);
    }

    if (filter.ageRange != null && filter.ageRange!.isNotEmpty) {
      final now = DateTime.now();
      if (filter.ageRange == '8–14') {
        final d8 = now.subtract(const Duration(days: 8)).toIso8601String().split('T').first;
        final d14 = now.subtract(const Duration(days: 14)).toIso8601String().split('T').first;
        query = query.lte('application_date', d8).gte('application_date', d14);
      } else if (filter.ageRange == '15–29') {
        final d15 = now.subtract(const Duration(days: 15)).toIso8601String().split('T').first;
        final d29 = now.subtract(const Duration(days: 29)).toIso8601String().split('T').first;
        query = query.lte('application_date', d15).gte('application_date', d29);
      } else if (filter.ageRange == '30+') {
        final d30 = now.subtract(const Duration(days: 30)).toIso8601String().split('T').first;
        query = query.lte('application_date', d30);
      }
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(page * _pageSize, (page + 1) * _pageSize - 1);

    final list = List<Map<String, dynamic>>.from(response);

    // Filter by installation in-memory if needed
    List<Map<String, dynamic>> filteredList = list;
    if (filter.installation != null && filter.installation != 'All') {
      filteredList = list.where((c) {
        final tasks = c['site_installation_tasks'] as List? ?? [];
        final structure = tasks.firstWhere((t) => t['task_type'] == 'Structure Installation', orElse: () => null);
        final panel = tasks.firstWhere((t) => t['task_type'] == 'Panel Uploading', orElse: () => null);
        final wiring = tasks.firstWhere((t) => t['task_type'] == 'Wiring', orElse: () => null);
        
        final isStructureCompleted = structure != null && structure['status'] == 'Completed';
        final isPanelCompleted = panel != null && panel['status'] == 'Completed';
        final isWiringCompleted = wiring != null && wiring['status'] == 'Completed';
        
        if (filter.installation == 'Structure Pending') {
          return !isStructureCompleted;
        }
        if (filter.installation == 'Structure Completed') {
          return isStructureCompleted;
        }
        if (filter.installation == 'Panel Pending') {
          return isStructureCompleted && !isPanelCompleted;
        }
        if (filter.installation == 'Panel Completed') {
          return isPanelCompleted;
        }
        if (filter.installation == 'Wiring Pending') {
          return isStructureCompleted && !isWiringCompleted;
        }
        if (filter.installation == 'Wiring Completed') {
          return isWiringCompleted;
        }
        if (filter.installation == 'Installation Completed') {
          return isStructureCompleted && isPanelCompleted && isWiringCompleted;
        }
        return true;
      }).toList();
    }

    if (list.length < _pageSize) {
      _hasMore = false;
    }
    return filteredList;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || state.value == null) return;
    _isLoadingMore = true;
    try {
      final nextPage = _page + 1;
      final newItems = await _fetchPage(nextPage);
      if (newItems.isNotEmpty) {
        _page = nextPage;
        state = AsyncData([...state.value!, ...newItems]);
      }
    } catch (_) {
      // Ignored
    } finally {
      _isLoadingMore = false;
    }
  }

  bool _matchesFilter(Map<String, dynamic> c, CustomerFilter f) {
    if (f.query.isNotEmpty) {
      final queryLower = f.query.toLowerCase();
      final name = (c['name'] ?? '').toString().toLowerCase();
      final cid = (c['customer_id'] ?? '').toString().toLowerCase();
      final mobile = (c['mobile'] ?? '').toString().toLowerCase();
      final cons = (c['consumer_number'] ?? '').toString().toLowerCase();
      final village = (c['village'] ?? '').toString().toLowerCase();
      final pmAppId = (c['pm_surya_ghar_application_id'] ?? '').toString().toLowerCase();
      if (!name.contains(queryLower) &&
          !cid.contains(queryLower) &&
          !mobile.contains(queryLower) &&
          !cons.contains(queryLower) &&
          !village.contains(queryLower) &&
          !pmAppId.contains(queryLower)) {
        return false;
      }
    }
    
    if (f.stages.isNotEmpty && !f.stages.contains(c['stage'])) {
      return false;
    }
    
    if (f.village != null && f.village!.isNotEmpty && c['village'] != f.village) {
      return false;
    }
    
    if (f.loan != null && f.loan != 'All') {
      final req = c['loan_required'] == true;
      if (f.loan == 'Yes' && !req) return false;
      if (f.loan == 'No' && req) return false;
    }

    if (f.priority == true && c['priority'] != true) {
      return false;
    }

    if (f.ageRange != null && f.ageRange!.isNotEmpty) {
      final ageCategory = AppDateUtils.ageCategory(c['application_date']);
      if (ageCategory != f.ageRange) {
        return false;
      }
    }
    
    if (f.installation != null && f.installation != 'All') {
      if (c['stage'] != 'Installation') return false;
      final tasks = c['site_installation_tasks'] as List? ?? [];
      final structure = tasks.firstWhere((t) => t['task_type'] == 'Structure Installation', orElse: () => null);
      final panel = tasks.firstWhere((t) => t['task_type'] == 'Panel Uploading', orElse: () => null);
      final wiring = tasks.firstWhere((t) => t['task_type'] == 'Wiring', orElse: () => null);
      
      final isStructureCompleted = structure != null && structure['status'] == 'Completed';
      final isPanelCompleted = panel != null && panel['status'] == 'Completed';
      final isWiringCompleted = wiring != null && wiring['status'] == 'Completed';
      
      if (f.installation == 'Structure Pending') {
        if (isStructureCompleted) return false;
      }
      if (f.installation == 'Structure Completed') {
        if (!isStructureCompleted) return false;
      }
      if (f.installation == 'Panel Pending') {
        if (!isStructureCompleted || isPanelCompleted) return false;
      }
      if (f.installation == 'Panel Completed') {
        if (!isPanelCompleted) return false;
      }
      if (f.installation == 'Wiring Pending') {
        if (!isStructureCompleted || isWiringCompleted) return false;
      }
      if (f.installation == 'Wiring Completed') {
        if (!isWiringCompleted) return false;
      }
      if (f.installation == 'Installation Completed') {
        if (!isStructureCompleted || !isPanelCompleted || !isWiringCompleted) return false;
      }
    }
    
    return true;
  }

  Future<void> upsertCustomer(String id) async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final response = await supabase
          .from('customers')
          .select('*, site_installation_tasks(task_type, status)')
          .eq('id', id)
          .single();
      
      if (state.value != null) {
        final current = List<Map<String, dynamic>>.from(state.value!);
        final idx = current.indexWhere((c) => c['id'] == id);
        
        final filter = ref.read(customerFilterProvider);
        final matches = _matchesFilter(response, filter);
        
        if (idx >= 0) {
          if (matches) {
            current[idx] = response;
          } else {
            current.removeAt(idx);
          }
        } else {
          if (matches) {
            current.insert(0, response);
          }
        }
        state = AsyncData(current);
      }
    } catch (e) {
      // Ignored
    }
  }

  void removeCustomer(String id) {
    if (state.value != null) {
      final current = state.value!.where((c) => c['id'] != id).toList();
      state = AsyncData(current);
    }
  }
}

final customerListProvider = AsyncNotifierProvider<CustomerListNotifier, List<Map<String, dynamic>>>(CustomerListNotifier.new);

final customerHistoryProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  final supabase = ref.watch(supabaseClientProvider);
  final res = await supabase
      .from('stage_history')
      .select('*, staff(name, profile_photo_url)')
      .eq('customer_id', customerId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(res);
});

final customerTasksProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  final supabase = ref.watch(supabaseClientProvider);
  final res = await supabase
      .from('tasks')
      .select('*')
      .eq('customer_id', customerId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(res);
});

final creatorNameProvider = FutureProvider.autoDispose.family<String?, String?>((ref, creatorId) async {
  if (creatorId == null) return null;
  final supabase = ref.watch(supabaseClientProvider);
  final res = await supabase
      .from('staff')
      .select('name')
      .eq('id', creatorId)
      .maybeSingle();
  return res?['name']?.toString();
});

final installationTasksProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  final supabase = ref.watch(supabaseClientProvider);
  final response = await supabase
      .from('site_installation_tasks')
      .select()
      .eq('customer_id', customerId);
  return List<Map<String, dynamic>>.from(response);
});

final villageListProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final response = await supabase
      .from('customers')
      .select('village')
      .not('village', 'is', null);
  final list = List<Map<String, dynamic>>.from(response);
  final villages = list
      .map((e) => e['village'].toString().trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  villages.sort();
  return villages;
});

