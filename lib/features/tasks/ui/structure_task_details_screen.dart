import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/structure_task_details_model.dart';
import 'widgets/limited_customer_view_sheet.dart';
import 'widgets/installation_photos_section.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/services/permission_service.dart';

class StructureTaskDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;

  const StructureTaskDetailsScreen({super.key, required this.task});

  @override
  ConsumerState<StructureTaskDetailsScreen> createState() => _StructureTaskDetailsScreenState();
}

class _StructureTaskDetailsScreenState extends ConsumerState<StructureTaskDetailsScreen> {
  bool _isLoading = true;
  StructureTaskDetailsModel? _taskDetails;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = ref.read(supabaseClientProvider);
      final taskId = widget.task['id'] ?? widget.task['task_id'];

      try {
        final rpcRes = await supabase.rpc('get_structure_task_details', params: {'p_task_id': taskId});
        if (rpcRes != null) {
          final modelData = Map<String, dynamic>.from(rpcRes as Map);
          setState(() {
            _taskDetails = StructureTaskDetailsModel.fromJson(modelData);
            _isLoading = false;
          });
          return;
        }
      } catch (rpcErr) {
        debugPrint('[StructureTaskDetailsScreen] RPC notice: $rpcErr');
      }

      final res = await supabase
          .from('tasks')
          .select('''
            id, name, description, due_date, priority, status, completion_remark, created_at, customer_id,
            customers!inner (id, name, mobile, address, village, consumer_number)
          ''')
          .eq('id', taskId)
          .maybeSingle();

      if (res == null) {
        setState(() {
          _errorMessage = 'Task details not found or access denied.';
          _isLoading = false;
        });
        return;
      }

      final instRes = await supabase
          .from('site_installation_tasks')
          .select('id, task_type, status, remark')
          .eq('customer_id', res['customer_id']);

      final combined = Map<String, dynamic>.from(res);
      combined['installation_tasks'] = instRes;

      setState(() {
        _taskDetails = StructureTaskDetailsModel.fromJson(combined);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading task details: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _makeCall(String phone) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(phoneUri)) await launchUrl(phoneUri);
  }

  Future<void> _openMap(String address) async {
    final query = Uri.encodeComponent(address);
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(googleMapsUrl)) await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
  }

  Future<void> _startTask() async {
    if (_taskDetails == null) return;
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);

      await supabase.from('tasks').update({
        'status': 'in_progress',
        'started_by': user?.id,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _taskDetails!.taskId);

      await ActivityLogger.log(
        supabase: supabase,
        customerId: _taskDetails!.customerId,
        action: 'structure_installation_started',
        description: 'Structure Installer started task: ${_taskDetails!.taskName}',
        performedBy: user?.id ?? '',
      );

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task started!')));
      await _loadDetails();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeTask() async {
    if (_taskDetails == null) return;
    final remarkController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Structure Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Confirm that structure installation is completed.'),
            const SizedBox(height: 12),
            TextField(
              controller: remarkController,
              decoration: const InputDecoration(labelText: 'Remarks', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);

      await supabase.from('tasks').update({
        'status': 'completed',
        'completed_by': user?.id,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'completion_remark': remarkController.text.trim(),
      }).eq('id', _taskDetails!.taskId);

      await ActivityLogger.log(
        supabase: supabase,
        customerId: _taskDetails!.customerId,
        action: 'structure_installation_completed',
        description: 'Structure Installation completed by installer',
        performedBy: user?.id ?? '',
      );

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task Completed!')));
      await _loadDetails();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openLimitedCustomerView() {
    if (_taskDetails == null) return;
    LimitedCustomerViewSheet.show(
      context: context,
      customerName: _taskDetails!.customerName,
      mobile: _taskDetails!.customerMobile,
      address: _taskDetails!.address,
      village: _taskDetails!.village,
      applicationId: _taskDetails!.applicationId,
      roleCategory: StaffCategory.structureInstaller,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('STRUCTURE INSTALLATION TASK')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _taskDetails == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('STRUCTURE INSTALLATION TASK')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Task details unavailable'),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadDetails, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final d = _taskDetails!;

    return Scaffold(
      appBar: AppBar(title: const Text('STRUCTURE INSTALLATION TASK')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Task Name Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.taskName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Priority: ${d.priority.toUpperCase()} • Status: ${d.status.toUpperCase()}', style: TextStyle(color: Colors.blue.shade900, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Customer Card (Compact Limited)
            const Text('CUSTOMER INFO', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                onTap: _openLimitedCustomerView,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(d.customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue))),
                          const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Mobile: ${d.customerMobile}'),
                      Text('Address: ${d.address}'),
                      if (d.applicationId != null) Text('App ID: ${d.applicationId}'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('CALL'),
                              onPressed: () => _makeCall(d.customerMobile),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.map, size: 16),
                              label: const Text('MAP'),
                              onPressed: () => _openMap(d.address),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Installation Instructions
            if (d.taskDescription != null && d.taskDescription!.isNotEmpty) ...[
              const Text('INSTALLATION INSTRUCTIONS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(d.taskDescription!),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Structure & Panel Photos Section
            InstallationPhotosSection(
              taskId: d.taskId,
              customerId: d.customerId,
              userRole: 'installer',
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START'),
                    onPressed: d.status == 'completed' ? null : _startTask,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('COMPLETE'),
                    onPressed: d.status == 'completed' ? null : _completeTask,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
