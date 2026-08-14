import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_utils.dart';
import '../providers/task_provider.dart';
import 'task_details_screen.dart';

class IncompleteTasksScreen extends ConsumerStatefulWidget {
  const IncompleteTasksScreen({super.key});

  @override
  ConsumerState<IncompleteTasksScreen> createState() => _IncompleteTasksScreenState();
}

class _IncompleteTasksScreenState extends ConsumerState<IncompleteTasksScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  // Filters
  String? _selectedStaffName;
  String? _selectedCustomerName;
  String? _selectedReason;
  DateTime? _selectedDate;

  // Pagination
  int _pageSize = 15;
  int _currentPage = 1;

  void _resetFilters() {
    setState(() {
      _selectedStaffName = null;
      _selectedCustomerName = null;
      _selectedReason = null;
      _selectedDate = null;
      _currentPage = 1;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(incompleteTaskListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('INCOMPLETE TASKS', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(incompleteTaskListProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim().toLowerCase();
                  _currentPage = 1; // Reset to page 1 on search change
                });
              },
              decoration: InputDecoration(
                hintText: 'Search Task, Customer, Staff, App ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _currentPage = 1;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),

          // Filters panel
          _buildFiltersPanel(listAsync.value ?? []),

          // Task List
          Expanded(
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
              data: (tasks) {
                // Apply Search & Filters
                var filtered = tasks.where((t) {
                  final customer = t['customers'] as Map<String, dynamic>?;
                  final customerName = (customer?['name'] ?? '').toString().toLowerCase();
                  final customerMobile = (customer?['mobile'] ?? '').toString();
                  final appId = (customer?['pm_surya_ghar_application_id'] ?? '').toString().toLowerCase();
                  final taskName = (t['name'] ?? '').toString().toLowerCase();
                  final reason = (t['not_completed_reason'] ?? '').toString();
                  
                  // Extract assigned staff names
                  List<String> staffNames = [];
                  if (t['task_staff'] != null) {
                    final staffList = t['task_staff'] as List;
                    for (var s in staffList) {
                      final name = (s['staff'] as Map?)?['name'];
                      if (name != null) staffNames.add(name.toString().toLowerCase());
                    }
                  } else if (t['task_staff_list'] != null) {
                    final staffList = t['task_staff_list'] as List;
                    for (var s in staffList) {
                      final name = (s['staff'] as Map?)?['name'];
                      if (name != null) staffNames.add(name.toString().toLowerCase());
                    }
                  }

                  // 1. Search Query Check
                  if (_searchQuery.isNotEmpty) {
                    final matchesSearch = taskName.contains(_searchQuery) ||
                        customerName.contains(_searchQuery) ||
                        customerMobile.contains(_searchQuery) ||
                        appId.contains(_searchQuery) ||
                        staffNames.any((name) => name.contains(_searchQuery));
                    if (!matchesSearch) return false;
                  }

                  // 2. Reason Filter
                  if (_selectedReason != null && reason != _selectedReason) {
                    return false;
                  }

                  // 3. Staff Filter
                  if (_selectedStaffName != null) {
                    final matchesStaff = staffNames.any((name) => name == _selectedStaffName!.toLowerCase());
                    if (!matchesStaff) return false;
                  }

                  // 4. Customer Filter
                  if (_selectedCustomerName != null && customerName != _selectedCustomerName!.toLowerCase()) {
                    return false;
                  }

                  // 5. Date Filter
                  if (_selectedDate != null && t['not_completed_at'] != null) {
                    final taskDate = DateTime.parse(t['not_completed_at']).toLocal();
                    final sameDate = taskDate.year == _selectedDate!.year &&
                        taskDate.month == _selectedDate!.month &&
                        taskDate.day == _selectedDate!.day;
                    if (!sameDate) return false;
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No incomplete tasks found.', style: TextStyle(color: Colors.grey, fontSize: 16)));
                }

                // Apply pagination
                final totalItems = filtered.length;
                final totalPages = (totalItems / _pageSize).ceil();
                final startIndex = (_currentPage - 1) * _pageSize;
                final endIndex = startIndex + _pageSize > totalItems ? totalItems : startIndex + _pageSize;
                final paginatedList = filtered.sublist(startIndex, endIndex);

                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: paginatedList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final t = paginatedList[index];
                          final customer = t['customers'] as Map<String, dynamic>?;
                          final customerName = customer?['name'] ?? 'N/A';
                          final taskName = t['name'] ?? 'N/A';
                          final reason = t['not_completed_reason'] ?? 'N/A';
                          final remark = t['not_completed_remark'] ?? '';
                          final timestamp = t['not_completed_at'] != null
                              ? AppDateUtils.formatDateTime(t['not_completed_at'])
                              : 'N/A';

                          // Extract assigned staff display string
                          List<String> staffDisplayList = [];
                          if (t['task_staff'] != null) {
                            for (var s in (t['task_staff'] as List)) {
                              final name = (s['staff'] as Map?)?['name'];
                              if (name != null) staffDisplayList.add(name.toString());
                            }
                          } else if (t['task_staff_list'] != null) {
                            for (var s in (t['task_staff_list'] as List)) {
                              final name = (s['staff'] as Map?)?['name'];
                              if (name != null) staffDisplayList.add(name.toString());
                            }
                          }
                          final staffStr = staffDisplayList.isEmpty ? 'Unassigned' : staffDisplayList.join(', ');

                          return Card(
                            elevation: 2,
                            shadowColor: Colors.orange.withOpacity(0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.orange.withOpacity(0.2)),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TaskDetailsScreen(task: t),
                                  ),
                                ).then((_) => ref.invalidate(incompleteTaskListProvider));
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            taskName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Customer: $customerName', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text('Staff: $staffStr', style: const TextStyle(color: Colors.black54)),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Reason: $reason',
                                            style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          if (remark.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Remark: $remark',
                                              style: const TextStyle(color: Colors.black87, fontSize: 12),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Updated: $timestamp', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Pagination Buttons
                    if (totalPages > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                            ),
                            Text('Page $_currentPage of $totalPages', style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersPanel(List<Map<String, dynamic>> tasks) {
    // Generate dropdown items from loaded tasks
    final reasons = tasks.map((t) => (t['not_completed_reason'] ?? '').toString()).where((r) => r.isNotEmpty).toSet().toList();
    
    final staffNames = <String>{};
    for (var t in tasks) {
      if (t['task_staff'] != null) {
        for (var s in (t['task_staff'] as List)) {
          final name = (s['staff'] as Map?)?['name'];
          if (name != null) staffNames.add(name.toString());
        }
      } else if (t['task_staff_list'] != null) {
        for (var s in (t['task_staff_list'] as List)) {
          final name = (s['staff'] as Map?)?['name'];
          if (name != null) staffNames.add(name.toString());
        }
      }
    }

    final customerNames = tasks.map((t) => ((t['customers'] as Map?)?['name'] ?? '').toString()).where((c) => c.isNotEmpty).toSet().toList();

    final bool hasActiveFilters = _selectedStaffName != null || _selectedCustomerName != null || _selectedReason != null || _selectedDate != null;

    return ExpansionTile(
      leading: Icon(Icons.filter_list, color: hasActiveFilters ? Colors.orange : Colors.grey),
      title: Text(
        hasActiveFilters ? 'Filters Active' : 'Filter Tasks',
        style: TextStyle(
          color: hasActiveFilters ? Colors.orange.shade800 : Colors.black87,
          fontWeight: hasActiveFilters ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Row(
          children: [
            // Reason Dropdown
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedReason,
                hint: const Text('Reason'),
                isExpanded: true,
                items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (val) => setState(() { _selectedReason = val; _currentPage = 1; }),
              ),
            ),
            const SizedBox(width: 8),
            // Staff Dropdown
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedStaffName,
                hint: const Text('Staff'),
                isExpanded: true,
                items: staffNames.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() { _selectedStaffName = val; _currentPage = 1; }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Customer Dropdown
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedCustomerName,
                hint: const Text('Customer'),
                isExpanded: true,
                items: customerNames.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) => setState(() { _selectedCustomerName = val; _currentPage = 1; }),
              ),
            ),
            const SizedBox(width: 8),
            // Date Picker
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate ?? DateTime.now(),
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                      _currentPage = 1;
                    });
                  }
                },
                child: Text(_selectedDate == null
                    ? 'Date'
                    : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'),
              ),
            ),
          ],
        ),
        if (hasActiveFilters)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resetFilters,
              child: const Text('RESET FILTERS', style: TextStyle(color: Colors.red)),
            ),
          ),
      ],
    );
  }
}
