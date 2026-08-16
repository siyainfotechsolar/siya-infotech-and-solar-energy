import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/delivery_task_details_model.dart';
import 'widgets/limited_customer_view_sheet.dart';
import 'widgets/installation_photos_section.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/services/permission_service.dart';

class DeliveryTaskDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;

  const DeliveryTaskDetailsScreen({super.key, required this.task});

  @override
  ConsumerState<DeliveryTaskDetailsScreen> createState() => _DeliveryTaskDetailsScreenState();
}

class _DeliveryTaskDetailsScreenState extends ConsumerState<DeliveryTaskDetailsScreen> {
  bool _isLoading = true;
  DeliveryTaskDetailsModel? _taskDetails;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDeliveryTaskDetails();
  }

  Future<void> _loadDeliveryTaskDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = ref.read(supabaseClientProvider);
      final taskId = widget.task['id'] ?? widget.task['task_id'];

      // Attempt to load via RPC first for secure field restriction
      try {
        final rpcRes = await supabase.rpc('get_delivery_task_details', params: {'p_task_id': taskId});
        if (rpcRes != null) {
          final modelData = Map<String, dynamic>.from(rpcRes as Map);
          setState(() {
            _taskDetails = DeliveryTaskDetailsModel.fromJson(modelData);
            _isLoading = false;
          });
          return;
        }
      } catch (rpcErr) {
        debugPrint('[DeliveryTaskDetailsScreen] RPC notice: $rpcErr');
      }

      // Fallback query fetching ONLY authorized fields
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

      // Fetch materials assigned for this customer/delivery
      List<dynamic> matRes = [];
      try {
        final matData = await supabase
            .from('material_dispatches')
            .select('*')
            .eq('customer_id', res['customer_id']);
        matRes = List.from(matData);
      } catch (_) {
        try {
          final matData = await supabase
              .from('site_materials')
              .select('*, products(name)')
              .or('site_id.eq.${res['customer_id']},customer_id.eq.${res['customer_id']}');
          matRes = List.from(matData);
        } catch (_) {}
      }

      final photosRes = await supabase
          .from('task_attachments')
          .select('id, file_name, file_path, file_type, created_at')
          .eq('task_id', taskId);

      final combined = Map<String, dynamic>.from(res);
      combined['materials'] = matRes;
      combined['delivery_photos'] = photosRes;

      setState(() {
        _taskDetails = DeliveryTaskDetailsModel.fromJson(combined);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading delivery details: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _makeCall(String phone) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  Future<void> _openMap(String address) async {
    final query = Uri.encodeComponent(address);
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _startDelivery() async {
    if (_taskDetails == null) return;
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);

      final staffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
      final staffName = staffNameRes?['name'] ?? 'Delivery Staff';

      await supabase.from('tasks').update({
        'status': 'in_progress',
        'started_by': user?.id,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _taskDetails!.taskId);

      await ActivityLogger.log(
        supabase: supabase,
        customerId: _taskDetails!.customerId,
        action: 'delivery_started',
        description: '$staffName started delivery task: ${_taskDetails!.taskName}',
        performedBy: user?.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery marked In Progress!')));
      }
      await _loadDeliveryTaskDetails();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markDelivered() async {
    if (_taskDetails == null) return;
    final remarkController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure material delivery is completed?'),
            const SizedBox(height: 12),
            TextField(
              controller: remarkController,
              decoration: const InputDecoration(
                labelText: 'Delivery Remarks',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Delivered'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);

      final staffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
      final staffName = staffNameRes?['name'] ?? 'Delivery Staff';

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final formattedTime = AppDateUtils.formatDateTime(nowIso);

      await supabase.from('tasks').update({
        'status': 'completed',
        'completed_by': user?.id,
        'completed_at': nowIso,
        'completion_remark': remarkController.text.trim(),
      }).eq('id', _taskDetails!.taskId);

      // Also update material_dispatches for this customer with delivered_at timestamp (with fallback)
      try {
        await supabase.from('material_dispatches').update({
          'status': 'Delivered',
          'delivered_at': nowIso,
          'updated_at': nowIso,
        }).eq('customer_id', _taskDetails!.customerId);
      } catch (err) {
        if (err.toString().contains('delivered_at') || err.toString().contains('PGRST204')) {
          await supabase.from('material_dispatches').update({
            'status': 'Delivered',
            'updated_at': nowIso,
          }).eq('customer_id', _taskDetails!.customerId);
        }
      }

      await ActivityLogger.log(
        supabase: supabase,
        customerId: _taskDetails!.customerId,
        action: 'delivery_completed',
        description: '$staffName completed delivery on $formattedTime: ${_taskDetails!.taskName}',
        performedBy: user?.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Completed Successfully!')));
      }
      await _loadDeliveryTaskDetails();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markNotCompleted() async {
    if (_taskDetails == null) return;
    final reasons = [
      'Customer Not Available',
      'Site Address Wrong/Unreachable',
      'Customer Refused Delivery',
      'Vehicle/Transport Issue',
      'Material Damaged',
      'Weather Delay',
      'Other',
    ];
    String selectedReason = reasons.first;
    final remarkController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delivery Not Completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedReason,
                decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
                items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedReason = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkController,
                decoration: const InputDecoration(labelText: 'Additional Notes', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);
      final fullRemark = '$selectedReason: ${remarkController.text.trim()}';

      await supabase.from('tasks').update({
        'status': 'pending',
        'completion_remark': fullRemark,
      }).eq('id', _taskDetails!.taskId);

      await ActivityLogger.log(
        supabase: supabase,
        customerId: _taskDetails!.customerId,
        action: 'delivery_attempt_failed',
        description: 'Delivery Staff marked not completed ($selectedReason)',
        performedBy: user?.id ?? '',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Status Updated')));
      }
      await _loadDeliveryTaskDetails();
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
      address: _taskDetails!.deliveryAddress,
      village: _taskDetails!.village,
      applicationId: _taskDetails!.applicationId,
      roleCategory: StaffCategory.deliveryStaff,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('DELIVERY TASK')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _taskDetails == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('DELIVERY TASK')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Task details unavailable', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadDeliveryTaskDetails, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final d = _taskDetails!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DELIVERY TASK'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeliveryTaskDetails,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping, color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.taskName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Status: ${d.status.toUpperCase()}', style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (d.deliveredAt != null && d.deliveredAt!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Delivered: ${AppDateUtils.formatDateTime(d.deliveredAt)}', style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1. DELIVERY CUSTOMER CARD (Compact & Role Limited)
            const Text('CUSTOMER', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
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
                          Expanded(
                            child: Text(
                              d.customerName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ),
                          const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 14, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(d.customerMobile, style: const TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on, size: 14, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(child: Text(d.deliveryAddress, style: TextStyle(color: Colors.grey.shade800, fontSize: 13))),
                        ],
                      ),
                      if (d.applicationId != null && d.applicationId!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('App ID / Consumer: ${d.applicationId}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                      const Divider(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('CALL'),
                              onPressed: () => _makeCall(d.customerMobile),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
                              icon: const Icon(Icons.map, size: 16),
                              label: const Text('MAP'),
                              onPressed: () => _openMap(d.deliveryAddress),
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

            // 2. DELIVERY MATERIAL CARD (Assigned Materials Only)
            const Text('MATERIAL FOR THIS DELIVERY', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: d.materials.isEmpty
                    ? Text('No assigned material dispatches found for this site.', style: TextStyle(color: Colors.grey.shade600))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: d.materials.map((m) {
                          final type = m['material_type'] ?? 'Material';
                          final reqQty = m['required_qty'] ?? 1;
                          final dispQty = m['dispatched_qty'] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                const Icon(Icons.inventory_2, size: 18, color: Colors.orange),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    type,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Qty: $dispQty / $reqQty',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. DELIVERY PHOTOS & PROOF
            InstallationPhotosSection(
              taskId: d.taskId,
              customerId: d.customerId,
              userRole: 'delivery_staff',
            ),
            const SizedBox(height: 20),

            // 4. ACTIONS
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START DELIVERY'),
                    onPressed: d.status == 'completed' ? null : _startDelivery,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('MARK DELIVERED'),
                    onPressed: d.status == 'completed' ? null : _markDelivered,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.cancel),
              label: const Text('NOT COMPLETED'),
              onPressed: d.status == 'completed' ? null : _markNotCompleted,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
