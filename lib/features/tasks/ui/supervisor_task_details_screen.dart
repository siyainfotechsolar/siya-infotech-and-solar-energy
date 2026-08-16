import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'widgets/limited_customer_view_sheet.dart';
import 'widgets/installation_photos_section.dart';
import '../../../core/services/permission_service.dart';

class SupervisorTaskDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;

  const SupervisorTaskDetailsScreen({super.key, required this.task});

  @override
  ConsumerState<SupervisorTaskDetailsScreen> createState() => _SupervisorTaskDetailsScreenState();
}

class _SupervisorTaskDetailsScreenState extends ConsumerState<SupervisorTaskDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _taskData;
  Map<String, dynamic>? _customerData;

  @override
  void initState() {
    super.initState();
    _loadSupervisorData();
  }

  Future<void> _loadSupervisorData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final taskId = widget.task['id'] ?? widget.task['task_id'];

      final taskRes = await supabase
          .from('tasks')
          .select('''
            id, name, description, due_date, priority, status, completion_remark, created_at, customer_id,
            customers (id, name, mobile, address, village, consumer_number, system_size, stage)
          ''')
          .eq('id', taskId)
          .maybeSingle();

      if (taskRes != null) {
        setState(() {
          _taskData = taskRes;
          _customerData = taskRes['customers'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _openCustomerView() {
    if (_customerData == null) return;
    LimitedCustomerViewSheet.show(
      context: context,
      customerName: _customerData!['name'] ?? 'Customer',
      mobile: _customerData!['mobile'] ?? 'N/A',
      address: _customerData!['address'] ?? _customerData!['village'] ?? 'N/A',
      village: _customerData!['village'],
      applicationId: _customerData!['consumer_number'],
      roleCategory: StaffCategory.supervisor,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('SUPERVISOR TASK DETAILS')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final t = _taskData ?? widget.task;
    final c = _customerData;

    return Scaffold(
      appBar: AppBar(title: const Text('SUPERVISOR TASK DETAILS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Task Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['name'] ?? 'Task Details', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('Priority: ${t['priority'] ?? 'normal'} • Status: ${t['status'] ?? 'pending'}', style: TextStyle(color: Colors.teal.shade900, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Customer Summary Card
            if (c != null) ...[
              const Text('CUSTOMER SUMMARY', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: _openCustomerView,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['name'] ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
                        const SizedBox(height: 4),
                        Text('Mobile: ${c['mobile'] ?? 'N/A'}'),
                        Text('Location: ${c['village'] ?? c['address'] ?? 'N/A'}'),
                        if (c['system_size'] != null) Text('System Size: ${c['system_size']}'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Photos
            InstallationPhotosSection(
              taskId: t['id'] ?? '',
              customerId: t['customer_id'] ?? '',
              userRole: 'supervisor',
            ),
          ],
        ),
      ),
    );
  }
}
