import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/data_filter_service.dart';
import '../../../core/utils/priority_calculator.dart';

class CustomerFilter {
  final String query;
  final List<String> stages;
  final String? village;
  final String? ageRange;
  final bool? priority;
  final String? loan;
  final String? installation;
  final String subType; // 'leads', 'customers', or 'all'
  final String? loanStage;
  final String? loanIssueStatus;
  final String? bankName;
  final String priorityFilter; // 'ALL', 'HIGH', 'MEDIUM', 'NORMAL'
  final String sortBy; // 'priority', 'oldest_update', 'newest_customer'
  final String stageTag; // 'ALL', 'PM_SURYA_GHAR', 'LOAN', 'MATERIAL', 'WORK', 'PROBLEM', 'COMPLETED'

  CustomerFilter({
    this.query = '',
    this.stages = const [],
    this.village,
    this.ageRange,
    this.priority,
    this.loan = 'All',
    this.installation = 'All',
    this.subType = 'all',
    this.loanStage,
    this.loanIssueStatus,
    this.bankName,
    this.priorityFilter = 'ALL',
    this.sortBy = 'priority',
    this.stageTag = 'ALL',
  });

  CustomerFilter copyWith({
    String? query,
    List<String>? stages,
    String? village,
    String? ageRange,
    bool? priority,
    String? loan,
    String? installation,
    String? subType,
    String? loanStage,
    String? loanIssueStatus,
    String? bankName,
    String? priorityFilter,
    String? sortBy,
    String? stageTag,
  }) {
    return CustomerFilter(
      query: query ?? this.query,
      stages: stages ?? this.stages,
      village: village ?? this.village,
      ageRange: ageRange ?? this.ageRange,
      priority: priority ?? this.priority,
      loan: loan ?? this.loan,
      installation: installation ?? this.installation,
      subType: subType ?? this.subType,
      loanStage: loanStage ?? this.loanStage,
      loanIssueStatus: loanIssueStatus ?? this.loanIssueStatus,
      bankName: bankName ?? this.bankName,
      priorityFilter: priorityFilter ?? this.priorityFilter,
      sortBy: sortBy ?? this.sortBy,
      stageTag: stageTag ?? this.stageTag,
    );
  }
}

class CustomerFilterNotifier extends Notifier<CustomerFilter> {
  @override
  CustomerFilter build() => CustomerFilter(subType: 'all', stageTag: 'ALL');

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
    final perms = await ref.read(currentUserPermissionsProvider.future);

    List<Map<String, dynamic>> rawList = [];

    // Retrieve scoped customer IDs for permissions
    List<String> scopedCustomerIds = [];
    if (perms.dataAccessLevel == DataAccessLevel.assignedData && user != null) {
      scopedCustomerIds = await DataFilterService.getAuthorizedCustomerIds(
        supabase: supabase,
        userId: user.id,
        permissions: perms,
      );
    }

    final selectFields = DataFilterService.selectCustomerFields(perms);

    if (filter.subType == 'leads' || filter.subType == 'all') {
      var queryLeads = supabase.from('leads').select('*').neq('status', 'converted');
      if (filter.query.isNotEmpty) {
        queryLeads = queryLeads.or('name.ilike.%${filter.query}%,mobile.ilike.%${filter.query}%,village.ilike.%${filter.query}%,lead_id.ilike.%${filter.query}%');
      }
      if (filter.village != null && filter.village!.isNotEmpty) {
        queryLeads = queryLeads.eq('village', filter.village!);
      }
      final leadsRaw = await queryLeads;
      final leadsFormatted = List<Map<String, dynamic>>.from(leadsRaw).map((l) {
        final map = Map<String, dynamic>.from(l);
        map['stage'] = 'Lead';
        return map;
      }).toList();
      rawList.addAll(leadsFormatted);
    }

    if (filter.subType == 'customers' || filter.subType == 'all') {
      var queryCust = supabase.from('customers').select('$selectFields, site_installation_tasks(task_type, status), tasks(name, status)');
      if (scopedCustomerIds.isNotEmpty) {
        queryCust = queryCust.inFilter('id', scopedCustomerIds);
      }
      if (filter.query.isNotEmpty) {
        queryCust = queryCust.or('name.ilike.%${filter.query}%,mobile.ilike.%${filter.query}%,consumer_number.ilike.%${filter.query}%,customer_id.ilike.%${filter.query}%,village.ilike.%${filter.query}%,pm_surya_ghar_application_id.ilike.%${filter.query}%');
      }
      if (filter.village != null && filter.village!.isNotEmpty) {
        queryCust = queryCust.eq('village', filter.village!);
      }
      if (filter.subType == 'customers') {
        queryCust = queryCust.neq('stage', 'Lead');
      }
      final customersRaw = await queryCust;
      rawList.addAll(List<Map<String, dynamic>>.from(customersRaw));
    }

    // Map computed priority and update fields
    final mappedList = rawList.map((item) {
      final map = Map<String, dynamic>.from(item);
      
      final createdAt = map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null;
      final lastUpdate = map['last_meaningful_update'] != null ? DateTime.tryParse(map['last_meaningful_update']) : null;
      final loanIssueStatus = map['loan_issue_status'] as String?;
      final tasksList = [
        ...(map['tasks'] as List? ?? []),
        ...(map['site_installation_tasks'] as List? ?? []),
      ];

      final automatic = PriorityCalculator.calculateAutomatic(
        createdAt: createdAt,
        lastMeaningfulUpdate: lastUpdate,
        loanIssueStatus: loanIssueStatus,
        tasks: tasksList,
      );
      final manual = map['manual_priority'] as String?;
      final finalPriority = PriorityCalculator.calculateFinal(automatic: automatic, manual: manual);

      map['automatic_priority'] = automatic;
      map['final_priority'] = finalPriority;
      map['customer_age'] = PriorityCalculator.getCustomerAge(createdAt);
      map['last_update_label'] = PriorityCalculator.getLastUpdateLabel(lastUpdate, createdAt);
      map['days_since_update'] = PriorityCalculator.getDaysSinceUpdate(lastUpdate, createdAt);

      return map;
    }).toList();

    // Filter in-memory
    var filteredList = mappedList.where((c) => _matchesFilter(c, filter)).toList();

    // Sort in-memory
    if (filter.sortBy == 'priority') {
      filteredList.sort((a, b) {
        final valA = PriorityCalculator.priorityValue(a['final_priority'] ?? 'NORMAL');
        final valB = PriorityCalculator.priorityValue(b['final_priority'] ?? 'NORMAL');
        if (valA != valB) {
          return valB.compareTo(valA); // High priority first
        }
        final daysA = a['days_since_update'] as int? ?? 0;
        final daysB = b['days_since_update'] as int? ?? 0;
        return daysB.compareTo(daysA); // Oldest update first
      });
    } else if (filter.sortBy == 'oldest_update') {
      filteredList.sort((a, b) {
        final daysA = a['days_since_update'] as int? ?? 0;
        final daysB = b['days_since_update'] as int? ?? 0;
        return daysB.compareTo(daysA); // more days since update first
      });
    } else if (filter.sortBy == 'newest_customer') {
      filteredList.sort((a, b) {
        final ageA = a['customer_age'] as int? ?? 0;
        final ageB = b['customer_age'] as int? ?? 0;
        return ageA.compareTo(ageB); // smaller age (newest) first
      });
    }

    // Paginate in-memory
    final start = page * _pageSize;
    if (start >= filteredList.length) {
      _hasMore = false;
      return [];
    }
    final end = (page + 1) * _pageSize;
    final paginated = filteredList.sublist(start, end > filteredList.length ? filteredList.length : end);
    if (end >= filteredList.length) {
      _hasMore = false;
    }
    return paginated;
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
      final cid = (c['customer_id'] ?? c['lead_id'] ?? '').toString().toLowerCase();
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
    
    if (f.stageTag != 'ALL') {
      if (f.stageTag == 'PM_SURYA_GHAR') {
        if (c['stage'] != 'PM Surya Ghar Application') return false;
      } else if (f.stageTag == 'LOAN') {
        if (c['stage'] != 'Loan Processing') return false;
      } else if (f.stageTag == 'MATERIAL') {
        if (c['stage'] != 'Material Required' && c['stage'] != 'Material Dispatched') return false;
      } else if (f.stageTag == 'WORK') {
        if (c['stage'] != 'Installation' && c['stage'] != 'RTS' && c['stage'] != 'Subsidy') return false;
      } else if (f.stageTag == 'PROBLEM') {
        final hasOpenProblem = c['loan_issue_status'] == 'OPEN PROBLEM';
        final hasIncompleteTask = (c['tasks'] as List? ?? []).any((t) => t['status'] == 'not_completed' || t['status'] == 'incomplete') || 
                                  (c['site_installation_tasks'] as List? ?? []).any((t) => t['status'] == 'not_completed' || t['status'] == 'incomplete');
        if (!hasOpenProblem && !hasIncompleteTask) return false;
      } else if (f.stageTag == 'COMPLETED') {
        if (c['stage'] != 'Completed') return false;
      }
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
    
    if (f.priorityFilter != 'ALL') {
      if (c['final_priority'] != f.priorityFilter) return false;
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
  final results = <Map<String, dynamic>>[];

  try {
    final stageRes = await supabase
        .from('stage_history')
        .select('*, staff(name, profile_photo_url)')
        .eq('customer_id', customerId);

    for (final item in stageRes) {
      final m = Map<String, dynamic>.from(item);
      m['type'] = 'stage';
      m['title'] = 'Advanced to ${m['new_stage']}';
      results.add(m);
    }
  } catch (_) {}

  try {
    final actRes = await supabase
        .from('activity_log')
        .select('*, staff:performed_by(name, profile_photo_url)')
        .eq('customer_id', customerId);

    for (final item in actRes) {
      final m = Map<String, dynamic>.from(item);
      m['type'] = 'activity';
      m['title'] = m['description'] ?? m['action'] ?? 'Activity logged';
      results.add(m);
    }
  } catch (_) {}

  results.sort((a, b) {
    final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
    final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
    return db.compareTo(da);
  });

  return results;
});

final customerTasksProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  final supabase = ref.watch(supabaseClientProvider);
  final res = await supabase
      .from('tasks')
      .select('*, task_staff(staff(name))')
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
  
  // 1. Fetch existing site installation tasks
  var response = await supabase
      .from('site_installation_tasks')
      .select()
      .eq('customer_id', customerId);

  List<Map<String, dynamic>> tasks = List<Map<String, dynamic>>.from(response);

  // 2. Auto-seed default tasks if missing
  const defaultTaskTypes = ['Structure Installation', 'Wiring', 'Panel Uploading'];
  final existingTypes = tasks.map((t) => t['task_type'].toString()).toSet();
  final missingTypes = defaultTaskTypes.where((t) => !existingTypes.contains(t)).toList();

  if (missingTypes.isNotEmpty) {
    final seeds = missingTypes.map((type) => {
      'customer_id': customerId,
      'task_type': type,
      'status': 'Not Started',
    }).toList();

    try {
      final inserted = await supabase.from('site_installation_tasks').insert(seeds).select();
      tasks = [...tasks, ...List<Map<String, dynamic>>.from(inserted)];
    } catch (_) {
      // Fallback in-memory list if RLS/insert restricted
      for (final type in missingTypes) {
        tasks.add({
          'id': 'temp_$type',
          'customer_id': customerId,
          'task_type': type,
          'status': 'Not Started',
        });
      }
    }
  }

  // 3. Sync status from tasks table
  try {
    final generalTasks = await supabase
        .from('tasks')
        .select('name, status')
        .eq('customer_id', customerId);

    final generalList = List<Map<String, dynamic>>.from(generalTasks);

    for (final taskRow in tasks) {
      final type = taskRow['task_type'].toString().toLowerCase();
      // Match against general tasks
      for (final g in generalList) {
        final gName = g['name'].toString().toLowerCase();
        final gStatus = g['status'].toString().toLowerCase();

        if ((type.contains('wiring') && (gName.contains('wiring') || gName.contains('electrical') || gName.contains('wireman'))) ||
            (type.contains('structure') && (gName.contains('structure') || gName.contains('installer'))) ||
            (type.contains('panel') && (gName.contains('panel') || gName.contains('solar panel')))) {
          if (gStatus == 'completed') {
            taskRow['status'] = 'Completed';
          } else if (gStatus == 'in_progress' && taskRow['status'] != 'Completed') {
            taskRow['status'] = 'In Progress';
          }
        }
      }
    }
  } catch (_) {}

  // Sort tasks in standard order
  tasks.sort((a, b) {
    final indexA = defaultTaskTypes.indexOf(a['task_type'].toString());
    final indexB = defaultTaskTypes.indexOf(b['task_type'].toString());
    if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
    return a['task_type'].toString().compareTo(b['task_type'].toString());
  });

  return tasks;
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

