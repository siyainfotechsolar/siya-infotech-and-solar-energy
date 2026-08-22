import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'add_task_screen.dart';
import '../services/task_details_router.dart';
import '../providers/task_provider.dart';
import '../../../core/widgets/global_loading_overlay.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  final String initialFilterPriority;
  final String? initialStatusFilter;
  const TaskListScreen({
    super.key,
    this.initialIndex = 0,
    this.initialFilterPriority = 'all',
    this.initialStatusFilter,
  });

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _sortBy = 'date_desc'; // 'date_desc', 'date_asc', 'priority_desc', 'priority_asc'
  late String _filterPriority; // 'all', 'high', 'normal', 'low'
  String? _statusFilter;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterPriority = widget.initialFilterPriority;
    _statusFilter = widget.initialStatusFilter;
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  int _priorityRank(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high': return 3;
      case 'normal': return 2;
      case 'low': return 1;
      default: return 0;
    }
  }

  void _showSortFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Sort & Filter Tasks',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            _sortBy = 'date_desc';
                            _filterPriority = 'all';
                          });
                          setState(() {
                            _sortBy = 'date_desc';
                            _filterPriority = 'all';
                          });
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const Divider(),
                  const Text('SORT BY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _choiceChip(setSheetState, 'Newest First', _sortBy == 'date_desc', () {
                        setState(() => _sortBy = 'date_desc');
                      }),
                      _choiceChip(setSheetState, 'Oldest First', _sortBy == 'date_asc', () {
                        setState(() => _sortBy = 'date_asc');
                      }),
                      _choiceChip(setSheetState, 'Priority: High to Low', _sortBy == 'priority_desc', () {
                        setState(() => _sortBy = 'priority_desc');
                      }),
                      _choiceChip(setSheetState, 'Priority: Low to High', _sortBy == 'priority_asc', () {
                        setState(() => _sortBy = 'priority_asc');
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('FILTER BY PRIORITY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _choiceChip(setSheetState, 'All Priorities', _filterPriority == 'all', () {
                        setState(() => _filterPriority = 'all');
                      }),
                      _choiceChip(setSheetState, 'High Only', _filterPriority == 'high', () {
                        setState(() => _filterPriority = 'high');
                      }),
                      _choiceChip(setSheetState, 'Normal Only', _filterPriority == 'normal', () {
                        setState(() => _filterPriority = 'normal');
                      }),
                      _choiceChip(setSheetState, 'Low Only', _filterPriority == 'low', () {
                        setState(() => _filterPriority = 'low');
                      }),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _choiceChip(void Function(void Function()) setSheetState, String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setSheetState(() {
          onTap();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskListProvider);
    final roleAsync = ref.watch(userRoleProvider);
    final isFiltered = _filterPriority != 'all' || _sortBy != 'date_desc';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'PENDING'),
            Tab(text: 'COMPLETED'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isFiltered ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: isFiltered ? Colors.blue : null,
            ),
            onPressed: _showSortFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(taskListProvider),
          ),
          roleAsync.when(
            data: (role) {
              if (role != null && role != 'installer') {
                return IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddTaskScreen())),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: tasksAsync.when(
        data: (allTasks) {
          // Filter tasks based on search query
          var searched = allTasks;
          if (_searchQuery.isNotEmpty) {
            final query = _searchQuery.toLowerCase();
            searched = allTasks.where((t) {
              final taskName = (t['name'] ?? '').toString().toLowerCase();
              final customerName = ((t['customers'] as Map?)?['name'] ?? '').toString().toLowerCase();
              return taskName.contains(query) || customerName.contains(query);
            }).toList();
          }

          // Filter tasks based on priority
          var filtered = searched;
          if (_filterPriority != 'all') {
            filtered = searched.where((t) => (t['priority'] ?? 'normal').toLowerCase() == _filterPriority).toList();
          }

          // Filter tasks based on status
          var statusFiltered = filtered;
          if (_statusFilter != null && _statusFilter != 'all') {
            statusFiltered = filtered.where((t) => (t['status'] ?? '').toString().toLowerCase() == _statusFilter).toList();
          }

          // Filter tasks based on tabs
          final pendingTasks = statusFiltered.where((t) => t['status'] != 'completed').toList();
          final completedTasks = statusFiltered.where((t) => t['status'] == 'completed').toList();

          // Sort dynamically
          if (_sortBy == 'date_desc') {
            pendingTasks.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
            completedTasks.sort((a, b) => (b['completed_at'] ?? b['created_at'] ?? '').compareTo(a['completed_at'] ?? a['created_at'] ?? ''));
          } else if (_sortBy == 'date_asc') {
            pendingTasks.sort((a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''));
            completedTasks.sort((a, b) => (a['completed_at'] ?? a['created_at'] ?? '').compareTo(a['completed_at'] ?? a['created_at'] ?? ''));
          } else if (_sortBy == 'priority_desc') {
            pendingTasks.sort((a, b) => _priorityRank(b['priority']).compareTo(_priorityRank(a['priority'])));
            completedTasks.sort((a, b) => _priorityRank(b['priority']).compareTo(_priorityRank(a['priority'])));
          } else if (_sortBy == 'priority_asc') {
            pendingTasks.sort((a, b) => _priorityRank(a['priority']).compareTo(_priorityRank(b['priority'])));
            completedTasks.sort((a, b) => _priorityRank(a['priority']).compareTo(_priorityRank(b['priority'])));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '🔍 Search tasks...',
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              if (_statusFilter != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    children: [
                      Chip(
                        label: Text('Status: ${_statusFilter!.replaceAll('_', ' ').toUpperCase()}'),
                        onDeleted: () {
                          setState(() {
                            _statusFilter = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTaskList(pendingTasks),
                    _buildTaskList(completedTasks),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const GlobalDataLoadingWidget(message: 'Loading tasks...'),
        error: (e, st) => GlobalErrorWidget(
          message: 'Unable to load tasks.',
          onRetry: () => ref.invalidate(taskListProvider),
        ),
      ),
    );
  }


  Widget _buildTaskList(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      return const Center(child: Text('No tasks found.', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(taskListProvider);
        await ref.read(taskListProvider.future);
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          final customer = task['customers'] as Map<String, dynamic>?;
          final taskName = task['name'] ?? 'Unknown Task';
          final custName = customer?['name'] ?? 'No Customer';
          final status = task['status'] ?? 'pending';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(custName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(taskName, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(height: 6),
                        _buildStatusChip(status),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await TaskDetailsRouter.open(context, ref, task);
                      ref.invalidate(taskListProvider);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('OPEN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color c;
    switch (status.toLowerCase()) {
      case 'completed': c = Colors.green; break;
      case 'in_progress': c = Colors.blue; break;
      case 'not_completed': c = Colors.red; break;
      default: c = Colors.orange; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(status.toUpperCase(), style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
