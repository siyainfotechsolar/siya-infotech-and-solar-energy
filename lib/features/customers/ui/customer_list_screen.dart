import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/stage_config.dart';
import '../providers/customer_provider.dart';
import '../../../core/utils/priority_calculator.dart';
import 'customer_details_screen.dart';
import 'add_customer_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/widgets/global_loading_overlay.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  final bool filterPriority;
  final String? filterAgeRange;
  final List<String>? filterStages;
  final String? initialLoanStage;
  final String? initialLoanIssueStatus;
  final String? initialPriorityFilter;

  const CustomerListScreen({
    super.key,
    this.filterPriority = false,
    this.filterAgeRange,
    this.filterStages,
    this.initialLoanStage,
    this.initialLoanIssueStatus,
    this.initialPriorityFilter,
  });

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounceTimer;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(customerFilterProvider.notifier).updateFilter(CustomerFilter(
          priority: widget.filterPriority ? true : null,
          ageRange: widget.filterAgeRange,
          stages: widget.filterStages ?? const [],
          loanStage: widget.initialLoanStage,
          loanIssueStatus: widget.initialLoanIssueStatus,
          priorityFilter: widget.initialPriorityFilter ?? 'ALL',
        ));
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(customerListProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val, CustomerFilter filter) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      ref.read(customerFilterProvider.notifier).updateFilter(
        filter.copyWith(query: val),
      );
    });
  }

  bool _isPriority(String? dateStr) {
    if (dateStr == null) return false;
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date).inDays;
      return diff >= 15;
    } catch (_) {
      return false;
    }
  }

  String _statusLabel(String s, String prefix) {
    if (s == 'Completed' || s == '100%') return '$prefix 100%';
    if (s == 'In Progress' || s == '50%') return '$prefix 50%';
    return '$prefix 0%';
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete ${_selectedIds.length} customers?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;
    
    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.from('customers').delete().inFilter('id', _selectedIds.toList());
      setState(() => _selectedIds.clear());
      ref.invalidate(customerListProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customers deleted successfully')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _exportCustomers() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final supabase = ref.read(supabaseClientProvider);
      final response = await supabase
          .from('customers')
          .select('customer_id, name, mobile, consumer_number, address, village, system_size, stage, loan_required, application_date, pm_surya_ghar_application_id, reference, remarks')
          .order('created_at', ascending: false);
      
      final customers = List<Map<String, dynamic>>.from(response);
      
      final headers = [
        'Customer ID',
        'Customer Name',
        'Mobile',
        'Consumer Number',
        'Address',
        'Village',
        'System Size',
        'Application Stage',
        'Loan Required',
        'Application Date',
        'PM Surya Ghar Application ID',
        'Reference',
        'Remarks'
      ];
      
      final List<List<dynamic>> csvRows = [headers];
      for (var c in customers) {
        csvRows.add([
          c['customer_id'] ?? '',
          c['name'] ?? '',
          c['mobile'] ?? '',
          c['consumer_number'] ?? '',
          c['address'] ?? '',
          c['village'] ?? '',
          c['system_size'] ?? '',
          c['stage'] ?? '',
          c['loan_required'] == true ? 'Yes' : (c['loan_required'] == false ? 'No' : 'N/A'),
          c['application_date'] ?? '',
          c['pm_surya_ghar_application_id'] ?? '',
          c['reference'] ?? '',
          c['remarks'] ?? '',
        ]);
      }
      
      final csvString = Csv().encode(csvRows);
      final bytes = utf8.encode(csvString);
      
      if (mounted) Navigator.pop(context); // Close loading dialog
      
      final String? outputFile = await FilePicker.saveFile(
        fileName: 'customers_export.csv',
        bytes: bytes,
      );
      
      if (outputFile != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported successfully to: $outputFile')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Widget _buildFilterRow(CustomerFilter filter) {
    final stagesMap = {
      'ALL': 'ALL',
      'PM SURYA GHAR': 'PM_SURYA_GHAR',
      'LOAN': 'LOAN',
      'MATERIAL': 'MATERIAL',
      'WORK': 'WORK',
      'PROBLEM': 'PROBLEM',
      'COMPLETED': 'COMPLETED',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          ...stagesMap.entries.map((e) {
            final isSel = filter.stageTag == e.value;
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ChoiceChip(
                label: Text(
                  e.key,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                selected: isSel,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(customerFilterProvider.notifier).updateFilter(
                      filter.copyWith(stageTag: e.value),
                    );
                  }
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerListProvider);
    final filter = ref.watch(customerFilterProvider);
    final roleAsync = ref.watch(userRoleProvider);

    return Scaffold(
      appBar: _selectedIds.isNotEmpty
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIds.clear()),
              ),
              title: Text('${_selectedIds.length} Selected'),
              actions: [
                roleAsync.when(
                  data: (role) {
                    if (role == 'admin') {
                      return IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: _deleteSelected,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            )
          : AppBar(
              title: const Text('CUSTOMERS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1)),
              actions: [
                roleAsync.when(
                  data: (role) {
                    if (role != 'installer') {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download, color: Colors.blue),
                            tooltip: 'Export Customers',
                            onPressed: _exportCustomers,
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerScreen())),
                            icon: const Icon(Icons.add, color: Colors.blue),
                            label: const Text('NEW', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 4.0),
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('ALL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    selected: filter.subType == 'all',
                    onSelected: (selected) {
                      if (selected) {
                        _searchController.clear();
                        ref.read(customerFilterProvider.notifier).updateFilter(
                          CustomerFilter(subType: 'all'),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('LEAD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    selected: filter.subType == 'leads',
                    onSelected: (selected) {
                      if (selected) {
                        _searchController.clear();
                        ref.read(customerFilterProvider.notifier).updateFilter(
                          CustomerFilter(subType: 'leads'),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('CUSTOMER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    selected: filter.subType == 'customers',
                    onSelected: (selected) {
                      if (selected) {
                        _searchController.clear();
                        ref.read(customerFilterProvider.notifier).updateFilter(
                          CustomerFilter(subType: 'customers'),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '🔍 Search customer...',
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(customerFilterProvider.notifier).updateFilter(filter.copyWith(query: ''));
                        },
                      )
                    : null,
              ),
              onChanged: (val) => _onSearchChanged(val, filter),
            ),
          ),
          
          // Priority Filters & Sorting Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['ALL', 'HIGH', 'MEDIUM', 'NORMAL'].map((p) {
                        final isSel = filter.priorityFilter == p;
                        Color chipColor = Colors.grey.shade600;
                        if (p == 'HIGH') chipColor = Colors.red;
                        else if (p == 'MEDIUM') chipColor = Colors.orange;
                        else if (p == 'NORMAL') chipColor = Colors.green;

                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Text(
                              p, 
                              style: TextStyle(
                                fontSize: 11, 
                                fontWeight: FontWeight.bold,
                                color: isSel ? Colors.white : chipColor,
                              ),
                            ),
                            selected: isSel,
                            selectedColor: chipColor,
                            onSelected: (selected) {
                              if (selected) {
                                ref.read(customerFilterProvider.notifier).updateFilter(
                                  filter.copyWith(priorityFilter: p),
                                );
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: filter.sortBy,
                      icon: const Icon(Icons.sort, size: 16, color: Colors.blueGrey),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                      items: const [
                        DropdownMenuItem(value: 'priority', child: Text('Priority First')),
                        DropdownMenuItem(value: 'oldest_update', child: Text('Oldest Update')),
                        DropdownMenuItem(value: 'newest_customer', child: Text('Newest Customer')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(customerFilterProvider.notifier).updateFilter(
                            filter.copyWith(sortBy: val),
                          );
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: ref.watch(villageListProvider).when(
                      data: (villages) => DropdownButton<String>(
                        value: (filter.village == null || filter.village!.isEmpty) ? 'All' : filter.village!,
                        icon: const Icon(Icons.location_city, size: 16, color: Colors.blueGrey),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                        items: [
                          const DropdownMenuItem(value: 'All', child: Text('All Villages')),
                          ...villages.map((v) => DropdownMenuItem(value: v, child: Text(v))),
                        ],
                        onChanged: (val) {
                          final newVillage = (val == null || val == 'All') ? '' : val;
                          ref.read(customerFilterProvider.notifier).updateFilter(
                            filter.copyWith(village: newVillage),
                          );
                        },
                      ),
                      loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) => const Text('Error'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Inline Filters Row
          _buildFilterRow(filter),
          const SizedBox(height: 8),

          // Total Count Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL: ${customersAsync.value?.length ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13),
                ),
                if (filter.stages.isNotEmpty || (filter.village != null && filter.village!.isNotEmpty) || filter.loan != 'All' || filter.installation != 'All')
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      ref.read(customerFilterProvider.notifier).updateFilter(CustomerFilter());
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                    child: const Text('Reset Filters', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Customers List
          Expanded(
            child: customersAsync.when(
              data: (customers) {
                if (customers.isEmpty) return const Center(child: Text('No customers found.', style: TextStyle(color: Colors.grey)));
                
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(customerListProvider);
                    await ref.read(customerListProvider.future);
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: customers.length + 1,
                    itemBuilder: (context, index) {
                      if (index == customers.length) {
                        final hasMore = ref.read(customerListProvider.notifier).hasMore;
                        return hasMore
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : const SizedBox.shrink();
                      }

                      final c = customers[index];
                      final isSel = _selectedIds.contains(c['id']);
                      final finalPriority = c['final_priority'] ?? 'NORMAL';
                      final stageLabel = _getStageLabel(c);
                      final lastUpdateText = 'Last Update: ${c['last_update_label'] ?? 'Today'}';

                      int completedTasks = 0;
                      if (c['stage'] == 'Installation') {
                        final tasks = (c['site_installation_tasks'] as List?) ?? [];
                        final genTasks = (c['tasks'] as List?) ?? [];
                        
                        bool isDone(String key) {
                          for (var t in tasks) {
                            final type = (t['task_type'] ?? '').toString().toLowerCase();
                            final stat = (t['status'] ?? '').toString().toLowerCase();
                            if (type.contains(key.toLowerCase()) && (stat == 'completed' || stat == '100%')) return true;
                          }
                          for (var g in genTasks) {
                            final name = (g['name'] ?? '').toString().toLowerCase();
                            final stat = (g['status'] ?? '').toString().toLowerCase();
                            if ((name.contains(key.toLowerCase()) || (key == 'Wiring' && (name.contains('electrical') || name.contains('wireman')))) && stat == 'completed') return true;
                          }
                          return false;
                        }
                        if (isDone('Structure')) completedTasks++;
                        if (isDone('Panel')) completedTasks++;
                        if (isDone('Wiring')) completedTasks++;
                      }

                      return Card(
                        elevation: 1,
                        color: isSel ? Colors.blue.shade50 : Colors.white,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: isSel ? Colors.blue.shade300 : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          onLongPress: () {
                            roleAsync.whenData((role) {
                              if (role == 'admin') {
                                _toggleSelection(c['id']);
                              }
                            });
                          },
                          onTap: () {
                            if (_selectedIds.isNotEmpty) {
                              _toggleSelection(c['id']);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomerDetailsScreen(customer: c),
                                ),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          PriorityCalculator.getPriorityEmoji(finalPriority),
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          finalPriority,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: finalPriority == 'HIGH'
                                                ? Colors.red
                                                : (finalPriority == 'MEDIUM' ? Colors.orange : Colors.green),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      c['customer_id'] ?? c['lead_id'] ?? 'N/A',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  c['name'] ?? 'Unknown',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  c['mobile'] ?? 'N/A',
                                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                                ),
                                const SizedBox(height: 8),
                                const Divider(height: 1, thickness: 0.5),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            stageLabel,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blueGrey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (c['stage'] == 'Loan Processing' && c['loan_stage'] != null && c['loan_stage'].toString().isNotEmpty && c['loan_stage'] != 'NOT STARTED') ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Sub-stage: ${c['loan_stage']}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                          if (c['stage'] == 'Installation') ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Progress: $completedTasks/3 completed',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(
                                      lastUpdateText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: (c['days_since_update'] as int? ?? 0) >= 15
                                            ? Colors.red
                                            : ((c['days_since_update'] as int? ?? 0) >= 7 ? Colors.orange : Colors.grey.shade600),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const GlobalDataLoadingWidget(message: 'Loading customer list...'),
              error: (e, _) => GlobalErrorWidget(
                message: 'Unable to load customer list.',
                onRetry: () => ref.invalidate(customerListProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStageLabel(Map<String, dynamic> c) {
    final stage = c['stage'] ?? 'Lead';
    final loanIssueStatus = c['loan_issue_status'];
    final hasOpenProblem = loanIssueStatus == 'OPEN PROBLEM';
    
    final tasksList = [
      ...(c['tasks'] as List? ?? []),
      ...(c['site_installation_tasks'] as List? ?? []),
    ];
    final hasIncompleteTask = tasksList.any((t) => t['status'] == 'not_completed' || t['status'] == 'incomplete');
    
    if (hasOpenProblem || hasIncompleteTask) {
      return '⚠️ ON HOLD / PROBLEM';
    }
    
    if (stage == 'Lead') {
      return 'Enquiry / Lead';
    }
    if (stage == 'PM Surya Ghar Application') {
      return '🟡 NEW / PM SURYA GHAR';
    }
    if (stage == 'Loan Processing') {
      return '🏦 LOAN';
    }
    if (stage == 'Material Required' || stage == 'Material Dispatched') {
      return '📦 SITE MATERIAL';
    }
    if (stage == 'Installation') {
      return '🔧 INSTALLATION';
    }
    if (stage == 'RTS') {
      return '📄 RTS APPLICATION';
    }
    if (stage == 'Subsidy') {
      return '💰 SUBSIDY PENDING';
    }
    if (stage == 'Completed') {
      return '✅ COMPLETED';
    }
    return stage;
  }
}
