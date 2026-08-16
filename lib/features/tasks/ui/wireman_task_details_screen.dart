import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/wireman_task_details_model.dart';
import 'widgets/limited_customer_view_sheet.dart';
import 'widgets/installation_photos_section.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/widgets/barcode_scanner_dialog.dart';
import '../../../core/widgets/geo_tag_photo_capture_dialog.dart';
import '../../../core/notifications/notification_state.dart';

class WiremanTaskDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;

  const WiremanTaskDetailsScreen({super.key, required this.task});

  @override
  ConsumerState<WiremanTaskDetailsScreen> createState() => _WiremanTaskDetailsScreenState();
}

class _WiremanTaskDetailsScreenState extends ConsumerState<WiremanTaskDetailsScreen> {
  bool _isLoading = true;
  WiremanTaskDetailsModel? _taskDetails;
  String? _errorMessage;

  // Controllers & Local State
  final _capacityController = TextEditingController();
  final _inverterSerialController = TextEditingController();
  final _meterSerialController = TextEditingController();
  final _generationController = TextEditingController();
  
  int _panelQuantity = 6;
  final List<TextEditingController> _panelSerialControllers = [];

  // Work Item Statuses
  final Map<String, String> _workStatus = {
    'DC Wiring': 'PENDING',
    'AC Wiring': 'PENDING',
    'Inverter': 'PENDING',
    'Earthing': 'PENDING',
    'ACDB': 'PENDING',
    'DCDB': 'PENDING',
    'Meter': 'PENDING',
  };

  // Geo-Tag
  double? _geoLat;
  double? _geoLong;
  String? _geoTimestamp;

  @override
  void initState() {
    super.initState();
    _initPanelControllers();
    _loadDetails();
  }

  void _initPanelControllers() {
    _panelSerialControllers.clear();
    for (int i = 0; i < _panelQuantity; i++) {
      _panelSerialControllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _capacityController.dispose();
    _inverterSerialController.dispose();
    _meterSerialController.dispose();
    _generationController.dispose();
    for (var c in _panelSerialControllers) {
      c.dispose();
    }
    super.dispose();
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
        final rpcRes = await supabase.rpc('get_wireman_task_details', params: {'p_task_id': taskId});
        if (rpcRes != null) {
          final modelData = Map<String, dynamic>.from(rpcRes as Map);
          _applyModel(WiremanTaskDetailsModel.fromJson(modelData));
          return;
        }
      } catch (rpcErr) {
        debugPrint('[WiremanTaskDetailsScreen] RPC notice: $rpcErr');
      }

      Map<String, dynamic>? res;
      try {
        res = await supabase
            .from('tasks')
            .select('*, customers!inner (id, name, mobile, address, village, consumer_number)')
            .eq('id', taskId)
            .maybeSingle();
      } catch (_) {
        try {
          res = await supabase
              .from('tasks')
              .select('*, customers (id, name, mobile, address, village, consumer_number)')
              .eq('id', taskId)
              .maybeSingle();
        } catch (_) {}
      }

      if (res == null) {
        setState(() {
          _errorMessage = 'Task details not found or access denied.';
          _isLoading = false;
        });
        return;
      }

      List<dynamic> instRes = [];
      try {
        final instData = await supabase
            .from('site_installation_tasks')
            .select('id, task_type, status, remark')
            .eq('customer_id', res['customer_id']);
        instRes = List.from(instData);
      } catch (_) {}

      List<dynamic> matRes = [];
      try {
        final matData = await supabase
            .from('site_materials')
            .select('*, products(name)')
            .or('site_id.eq.${res['customer_id']},customer_id.eq.${res['customer_id']}');
        matRes = List.from(matData);
      } catch (_) {
        try {
          final matData = await supabase
              .from('material_dispatches')
              .select('*')
              .eq('customer_id', res['customer_id']);
          matRes = List.from(matData);
        } catch (_) {}
      }

      final combined = Map<String, dynamic>.from(res);
      combined['installation_tasks'] = instRes;
      combined['electrical_materials'] = matRes;

      _applyModel(WiremanTaskDetailsModel.fromJson(combined));
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading electrical task: $e';
        _isLoading = false;
      });
    }
  }

  void _applyModel(WiremanTaskDetailsModel model) {
    setState(() {
      _taskDetails = model;
      _isLoading = false;

      if (model.systemCapacity != null && model.systemCapacity!.isNotEmpty) {
        _capacityController.text = model.systemCapacity!;
      }
      if (model.inverterSerial != null && model.inverterSerial!.isNotEmpty) {
        _inverterSerialController.text = model.inverterSerial!;
      }
      if (model.meterNumber != null && model.meterNumber!.isNotEmpty) {
        _meterSerialController.text = model.meterNumber!;
      }
      if (model.generationReading != null && model.generationReading!.isNotEmpty) {
        _generationController.text = model.generationReading!;
      }

      _geoLat = model.geoLat;
      _geoLong = model.geoLong;
      _geoTimestamp = model.geoTimestamp;

      _panelQuantity = model.panelQuantity;
      _initPanelControllers();
      for (int i = 0; i < model.panelSerials.length && i < _panelQuantity; i++) {
        _panelSerialControllers[i].text = model.panelSerials[i];
      }

      if (model.electricalWorkStatus.isNotEmpty) {
        _workStatus.addAll(model.electricalWorkStatus);
      }
    });
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

  Future<void> _scanInverterSerial() async {
    final code = await BarcodeScannerDialog.show(
      context: context,
      title: 'Scan Inverter Serial Number',
      initialValue: _inverterSerialController.text,
    );
    if (code != null) {
      setState(() {
        _inverterSerialController.text = code;
      });
    }
  }

  Future<void> _scanPanelSerial(int index) async {
    final existingList = _panelSerialControllers.map((c) => c.text).toList();
    final code = await BarcodeScannerDialog.show(
      context: context,
      title: 'Scan Panel ${index + 1} Serial Number',
      initialValue: _panelSerialControllers[index].text,
      existingSerials: existingList,
      panelIndex: index,
    );

    if (code != null) {
      setState(() {
        _panelSerialControllers[index].text = code;
      });
    }
  }

  Future<void> _scanNextPanel() async {
    int targetIndex = -1;
    for (int i = 0; i < _panelSerialControllers.length; i++) {
      if (_panelSerialControllers[i].text.trim().isEmpty) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All panel serial numbers are already scanned!')),
      );
      return;
    }

    await _scanPanelSerial(targetIndex);
  }

  Future<void> _captureGeoTag() async {
    final result = await GeoTagPhotoCaptureDialog.startCapture(
      context,
      categoryTitle: 'Installation Site Geo-Tag',
    );

    if (result != null) {
      setState(() {
        _geoLat = result.latitude;
        _geoLong = result.longitude;
        _geoTimestamp = result.capturedAt;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 Geo-Tag Captured!\nLat: ${result.latitude.toStringAsFixed(6)}, Long: ${result.longitude.toStringAsFixed(6)} (${result.capturedAt})'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
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
        action: 'electrical_task_started',
        description: 'Wireman started electrical task: ${_taskDetails!.taskName}',
        performedBy: user?.id ?? '',
      );

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Electrical Task Started!')));
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
        title: const Text('Complete Electrical Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure electrical installation / wiring work is completed?'),
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
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final panelSerials = _panelSerialControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

      try {
        await supabase.from('tasks').update({
          'status': 'completed',
          'completed_by': user?.id,
          'completed_at': nowIso,
          'completion_remark': remarkController.text.trim(),
          'system_capacity': _capacityController.text.trim(),
          'inverter_serial': _inverterSerialController.text.trim(),
          'meter_number': _meterSerialController.text.trim(),
          'generation_reading': _generationController.text.trim(),
          'panel_serials': panelSerials,
          'electrical_work_status': _workStatus,
          'geo_lat': _geoLat,
          'geo_long': _geoLong,
          'geo_timestamp': _geoTimestamp,
        }).eq('id', _taskDetails!.taskId);
      } catch (_) {
        await supabase.from('tasks').update({
          'status': 'completed',
          'completed_by': user?.id,
          'completed_at': nowIso,
          'completion_remark': remarkController.text.trim(),
        }).eq('id', _taskDetails!.taskId);
      }

      final staffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
      final staffName = staffNameRes?['name'] ?? 'Wireman';

      await ActivityLogger.log(
        supabase: supabase,
        customerId: _taskDetails!.customerId,
        action: 'electrical_task_completed',
        description: '$staffName completed electrical task: ${_taskDetails!.taskName}',
        performedBy: user?.id,
      );

      final notificationRepo = ref.read(notificationRepositoryProvider);
      await notificationRepo.notifyAdmins(
        notificationType: 'TASK_COMPLETED',
        title: '⚡ Electrical Task Completed',
        message: 'Customer: ${_taskDetails!.customerName}\nWireman: $staffName\nTask: ${_taskDetails!.taskName}',
        relatedRecordId: _taskDetails!.customerId,
      );

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task Completed Successfully!'), backgroundColor: Colors.green));
      await _loadDetails();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markNotCompleted() async {
    if (_taskDetails == null) return;
    String selectedReason = 'Material Not Available';
    final detailsController = TextEditingController();

    const reasons = [
      'Material Not Available',
      'Site Not Ready',
      'Customer Not Available',
      'Technical Problem',
      'Weather Problem',
      'Electrical Work Pending',
      'Structure Work Pending',
      'Panel Work Pending',
      'Document/Permission Pending',
      'Other',
    ];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('TASK NOT COMPLETED'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedReason,
                decoration: const InputDecoration(labelText: 'Select Reason', border: OutlineInputBorder()),
                items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedReason = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailsController,
                decoration: InputDecoration(
                  labelText: selectedReason == 'Other' ? 'Reason Details (Required)' : 'Reason Details',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                if (selectedReason == 'Other' && detailsController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please enter reason details for "Other".')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
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
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final staffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
      final staffName = staffNameRes?['name'] ?? 'Wireman';

      final fullRemark = 'NOT COMPLETED ($selectedReason: ${detailsController.text.trim()})';
      try {
        await supabase.from('tasks').update({
          'status': 'not_completed',
          'incomplete_reason': selectedReason,
          'incomplete_details': detailsController.text.trim(),
          'incomplete_marked_by': staffName,
          'incomplete_at': nowIso,
          'completion_remark': fullRemark,
        }).eq('id', _taskDetails!.taskId);
      } catch (_) {
        await supabase.from('tasks').update({
          'status': 'not_completed',
          'completion_remark': fullRemark,
        }).eq('id', _taskDetails!.taskId);
      }

      await ActivityLogger.log(
        supabase: supabase,
        customerId: _taskDetails!.customerId,
        action: 'electrical_task_incomplete',
        description: '$staffName marked task incomplete ($selectedReason)',
        performedBy: user?.id,
      );

      final notificationRepo = ref.read(notificationRepositoryProvider);
      await notificationRepo.notifyAdmins(
        notificationType: 'TASK_INCOMPLETE',
        title: '⚠ Task Not Completed',
        message: 'Customer: ${_taskDetails!.customerName}\nWireman: $staffName\nReason: $selectedReason',
        relatedRecordId: _taskDetails!.customerId,
      );

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task Marked as Not Completed'), backgroundColor: Colors.orange));
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
      roleCategory: StaffCategory.wireman,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('WIREMAN TASK')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _taskDetails == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('WIREMAN TASK')),
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
    final isCompleted = d.status == 'completed';
    final isIncomplete = d.status == 'not_completed' || d.incompleteReason != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WIREMAN TASK'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDetails),
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
                color: isIncomplete ? Colors.red.shade50 : Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isIncomplete ? Colors.red.shade300 : Colors.purple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.taskName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Priority: ${d.priority.toUpperCase()} • Status: ${d.status.toUpperCase()}', style: TextStyle(color: isIncomplete ? Colors.red.shade900 : Colors.purple.shade900, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Incomplete Reason Banner (if marked incomplete)
            if (isIncomplete) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                        SizedBox(width: 8),
                        Text('⚠ NOT COMPLETED', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const Divider(height: 16),
                    Text('Reason:\n${d.incompleteReason ?? "Not specified"}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (d.incompleteDetails != null && d.incompleteDetails!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Details:\n${d.incompleteDetails}'),
                    ],
                    const SizedBox(height: 6),
                    Text('Marked By: ${d.incompleteMarkedBy ?? "Wireman"} • ${d.incompleteAt != null ? AppDateUtils.formatDateTime(d.incompleteAt) : ""}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 1. CUSTOMER INFO (Compact Limited)
            const Text('CUSTOMER', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
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
                          Expanded(child: Text(d.customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple))),
                          const Icon(Icons.info_outline, size: 18, color: Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('📞 ${d.customerMobile}'),
                      Text('📍 ${d.address}'),
                      if (d.applicationId != null) Text('PM Surya Ghar App ID: ${d.applicationId}'),
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

            // 2. ELECTRICAL WORK STATUS
            const Text('ELECTRICAL WORK', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: _workStatus.keys.map((itemKey) {
                    final currentStatus = _workStatus[itemKey] ?? 'PENDING';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(itemKey, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'PENDING', label: Text('PENDING', style: TextStyle(fontSize: 10))),
                              ButtonSegment(value: 'IN_PROGRESS', label: Text('IN PROGRESS', style: TextStyle(fontSize: 10))),
                              ButtonSegment(value: 'COMPLETED', label: Text('COMPLETED', style: TextStyle(fontSize: 10))),
                            ],
                            selected: {currentStatus},
                            onSelectionChanged: isCompleted ? null : (newSet) {
                              setState(() {
                                _workStatus[itemKey] = newSet.first;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. INSTALLATION DETAILS (System Capacity)
            const Text('INSTALLATION', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _capacityController,
                      readOnly: isCompleted,
                      decoration: const InputDecoration(
                        labelText: 'System Capacity (kW)',
                        hintText: 'e.g. 3 kW',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. INVERTER
            const Text('INVERTER', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inverterSerialController,
                            readOnly: isCompleted,
                            decoration: const InputDecoration(
                              labelText: 'Inverter Serial Number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (!isCompleted) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                            icon: const Icon(Icons.qr_code_scanner, size: 18),
                            label: const Text('SCAN'),
                            onPressed: _scanInverterSerial,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. PANELS & MULTIPLE SERIAL NUMBERS
            const Text('PANELS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Panel Quantity: $_panelQuantity', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        if (!isCompleted)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                            icon: const Icon(Icons.flash_on, size: 16),
                            label: const Text('SCAN NEXT PANEL'),
                            onPressed: _scanNextPanel,
                          ),
                      ],
                    ),
                    const Divider(height: 20),

                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _panelQuantity,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text('Panel ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _panelSerialControllers[index],
                                  readOnly: isCompleted,
                                  decoration: InputDecoration(
                                    hintText: 'Serial Number ${index + 1}',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (!isCompleted) ...[
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.qr_code_scanner, size: 16),
                                  label: const Text('SCAN'),
                                  onPressed: () => _scanPanelSerial(index),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 6. INSTALLATION PHOTOS & OPTIONAL UPLOADS
            InstallationPhotosSection(
              taskId: d.taskId,
              customerId: d.customerId,
              userRole: 'wireman',
            ),
            const SizedBox(height: 16),

            // 7. METER
            const Text('METER', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _meterSerialController,
                  readOnly: isCompleted,
                  decoration: const InputDecoration(
                    labelText: 'Meter Serial Number',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 8. GENERATION
            const Text('GENERATION', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _generationController,
                  readOnly: isCompleted,
                  decoration: const InputDecoration(
                    labelText: 'Generation Reading (kWh)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 9. GEO-TAG LOCATION
            const Text('LOCATION', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_geoLat != null && _geoLong != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Lat: ${_geoLat!.toStringAsFixed(4)}, Long: ${_geoLong!.toStringAsFixed(4)}\nTimestamp: ${_geoTimestamp ?? "Captured"}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                            icon: const Icon(Icons.my_location),
                            label: Text(_geoLat == null ? '📍 CAPTURE GEO TAG' : 'RE-CAPTURE GEO TAG'),
                            onPressed: isCompleted ? null : _captureGeoTag,
                          ),
                        ),
                        if (_geoLat != null) ...[
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.map),
                            label: const Text('MAP'),
                            onPressed: () => _openMap('${_geoLat!},${_geoLong!}'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 10. TASK ACTIONS (START, COMPLETE, NOT COMPLETED)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START TASK'),
                    onPressed: isCompleted ? null : _startTask,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('COMPLETE'),
                    onPressed: isCompleted ? null : _completeTask,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('NOT COMPLETED'),
              onPressed: isCompleted ? null : _markNotCompleted,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
