import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/stage_config.dart';
import '../providers/customer_provider.dart';
import 'add_customer_screen.dart';
import 'customer_details_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/widgets/global_loading_overlay.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  final bool filterPriority;
  final String? filterAgeRange;
  const CustomerListScreen({super.key, this.filterPriority = false, this.filterAgeRange});

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
      ref.read(customerFilterProvider.notifier).updateFilter(CustomerFilter(
        priority: widget.filterPriority ? true : null,
        ageRange: widget.filterAgeRange,
      ));
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
    if (s == 'Completed') return '$prefix ✓';
    if (s == 'In Progress') return '$prefix 50%';
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
    final villagesAsync = ref.watch(villageListProvider);
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          // Stage Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: DropdownButton<String>(
              value: filter.stages.isEmpty ? 'All' : filter.stages.first,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
              items: [
                const DropdownMenuItem(value: 'All', child: Text('All Stages')),
                ...StageConfig.stages.map((s) => DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: (val) {
                final newStages = (val == null || val == 'All') ? <String>[] : [val];
                ref.read(customerFilterProvider.notifier).updateFilter(
                  filter.copyWith(stages: newStages),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Village Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: villagesAsync.when(
              data: (villages) => DropdownButton<String>(
                value: filter.village ?? 'All',
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                underline: const SizedBox(),
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
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
              error: (_, __) => const Text('Village Error'),
            ),
          ),
          const SizedBox(width: 8),
          // Loan Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: DropdownButton<String>(
              value: filter.loan ?? 'All',
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All Loans')),
                DropdownMenuItem(value: 'Yes', child: Text('Loan: Yes')),
                DropdownMenuItem(value: 'No', child: Text('Loan: No')),
              ],
              onChanged: (val) {
                ref.read(customerFilterProvider.notifier).updateFilter(
                  filter.copyWith(loan: val ?? 'All'),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Installation Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: DropdownButton<String>(
              value: filter.installation ?? 'All',
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All Inst. Status')),
                DropdownMenuItem(value: 'Structure Pending', child: Text('Structure Pending')),
                DropdownMenuItem(value: 'Structure Completed', child: Text('Structure Completed')),
                DropdownMenuItem(value: 'Panel Pending', child: Text('Panel Pending')),
                DropdownMenuItem(value: 'Panel Completed', child: Text('Panel Completed')),
                DropdownMenuItem(value: 'Wiring Pending', child: Text('Wiring Pending')),
                DropdownMenuItem(value: 'Wiring Completed', child: Text('Wiring Completed')),
                DropdownMenuItem(value: 'Installation Completed', child: Text('Installation Completed')),
              ],
              onChanged: (val) {
                ref.read(customerFilterProvider.notifier).updateFilter(
                  filter.copyWith(installation: val ?? 'All'),
                );
              },
            ),
          ),
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
                      final priority = _isPriority(c['application_date']);

                      // Details for Sub-stages display if Stage is Installation
                      final tasks = c['site_installation_tasks'] as List? ?? [];
                      final structure = tasks.firstWhere((t) => t['task_type'] == 'Structure Installation', orElse: () => null)?['status'] ?? 'Not Started';
                      final panel = tasks.firstWhere((t) => t['task_type'] == 'Panel Uploading', orElse: () => null)?['status'] ?? 'Not Started';
                      final wiring = tasks.firstWhere((t) => t['task_type'] == 'Wiring', orElse: () => null)?['status'] ?? 'Not Started';

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
                              Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: c)));
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Line 1: Name and ID
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c['name'] ?? 'Unknown',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                                      ),
                                    ),
                                    Text(
                                      c['customer_id'] ?? 'N/A',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                
                                // Line 2: Mobile and Village
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      c['mobile'] ?? 'N/A',
                                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                                    ),
                                    Text(
                                      c['village'] ?? 'N/A',
                                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                                    ),
                                  ],
                                ),
                                if (c['pm_surya_ghar_application_id'] != null && c['pm_surya_ghar_application_id'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'PM Surya Ghar App ID: ${c['pm_surya_ghar_application_id']}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey),
                                  ),
                                ],
                                const SizedBox(height: 8),

                                // Priority Indicator If 15+ Days Old
                                if (priority) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: const Text(
                                      '🔴 PRIORITY',
                                      style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // Line 3: Stage and Age Days
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.lens, size: 10, color: StageConfig.stageColor(c['stage'])),
                                        const SizedBox(width: 6),
                                        Text(
                                          c['stage'] ?? 'Lead',
                                          style: TextStyle(
                                            color: StageConfig.stageColor(c['stage']),
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (c['application_date'] != null)
                                      Text(
                                        AppDateUtils.applicationAgeLabel(c['application_date']),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Sub-stages progress list or Loan Yes/No display
                                if (c['stage'] == 'Installation') ...[
                                  Text(
                                    '${_statusLabel(structure, 'Structure')}   ${_statusLabel(panel, 'Panel')}   ${_statusLabel(wiring, 'Wiring')}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                                  ),
                                ] else if (c['stage'] == 'Loan Processing') ...[
                                  Text(
                                    'Loan: ${c['loan_required'] == true ? "Yes" : "No"}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                                  ),
                                ],
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
}
