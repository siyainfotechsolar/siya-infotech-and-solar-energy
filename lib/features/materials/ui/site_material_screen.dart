import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/date_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/material_provider.dart';
import 'edit_material_sheet.dart';
import '../../../core/notifications/notification_state.dart';

// Provider to fetch dispatches for a customer
final customerDispatchesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  final supabase = ref.watch(supabaseClientProvider);
  final response = await supabase
      .from('material_dispatches')
      .select('*, staff(name)')
      .eq('customer_id', customerId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(response);
});

class SiteMaterialScreen extends ConsumerStatefulWidget {
  final String customerId;
  final String customerName;
  final String? pmSuryaGharApplicationId;

  const SiteMaterialScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.pmSuryaGharApplicationId,
  });

  @override
  ConsumerState<SiteMaterialScreen> createState() => _SiteMaterialScreenState();
}

class _SiteMaterialScreenState extends ConsumerState<SiteMaterialScreen> {
  bool _isCreatingDispatch = false;

  Future<void> _refreshAll() async {
    ref.invalidate(siteMaterialsProvider(widget.customerId));
    ref.invalidate(customerDispatchesProvider(widget.customerId));
  }

  Future<void> _showCreateDispatchDialog() async {
    final supabase = ref.read(supabaseClientProvider);
    setState(() => _isCreatingDispatch = true);

    try {
      // 1. Fetch active delivery staff
      final staffResponse = await supabase
          .from('staff')
          .select('id, name')
          .eq('role', 'delivery_staff')
          .eq('status', 'active')
          .order('name');
      final staffList = List<Map<String, dynamic>>.from(staffResponse);

      // 2. Fetch customer location details for notification message
      final custResponse = await supabase
          .from('customers')
          .select('village, address')
          .eq('id', widget.customerId)
          .maybeSingle();
      final village = custResponse?['village'] ?? custResponse?['address'] ?? 'N/A';

      setState(() => _isCreatingDispatch = false);

      if (!mounted) return;

      if (staffList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active Delivery Staff found to assign dispatches to.')),
        );
        return;
      }

      final formKey = GlobalKey<FormState>();
      String selectedMaterial = 'Solar Panel';
      final quantityController = TextEditingController(text: '1');
      Map<String, dynamic>? selectedStaff = staffList.first;

      await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Create Material Dispatch', style: TextStyle(fontWeight: FontWeight.bold)),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedMaterial,
                          decoration: const InputDecoration(labelText: 'Material Name', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'Solar Panel', child: Text('Solar Panel')),
                            DropdownMenuItem(value: 'Structure', child: Text('Structure')),
                            DropdownMenuItem(value: 'Inverter', child: Text('Inverter')),
                            DropdownMenuItem(value: 'Generation Meter', child: Text('Generation Meter')),
                            DropdownMenuItem(value: 'Wiring', child: Text('Wiring')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedMaterial = val;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: quantityController,
                          decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Required';
                            final qty = int.tryParse(val) ?? 0;
                            if (qty <= 0) return 'Must be greater than 0';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue: selectedStaff,
                          decoration: const InputDecoration(labelText: 'Assigned Delivery Staff', border: OutlineInputBorder()),
                          isExpanded: true,
                          items: staffList.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text(s['name'] ?? 'N/A'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedStaff = val;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                   ElevatedButton(
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final qty = int.parse(quantityController.text);
                        final staffId = selectedStaff!['id'];
                        final staffName = selectedStaff!['name'];

                        Navigator.pop(context);
                        setState(() => _isCreatingDispatch = true);

                        // Capture messenger from widget context before async gap
                        final messenger = ScaffoldMessenger.of(this.context);

                        try {
                          // Insert dispatch
                          await supabase.from('material_dispatches').insert({
                            'customer_id': widget.customerId,
                            'delivery_staff_id': staffId,
                            'material_name': selectedMaterial,
                            'quantity': qty,
                            'status': 'Pending',
                          });

                          // Create Notification for the Delivery Staff via Edge Function (inserts DB + sends FCM push)
                          final notificationRepo = ref.read(notificationRepositoryProvider);
                          await notificationRepo.sendNotification(
                            recipientUserId: staffId,
                            notificationType: 'NEW_DISPATCH_ASSIGNED',
                            title: '🔔 New Delivery Assigned',
                            message: 'Customer:\n${widget.customerName}\n\nSite:\n$village\n\nMaterial:\n$selectedMaterial × $qty',
                          );

                          _refreshAll();

                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Dispatch created & notification sent to $staffName!'), backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(SnackBar(content: Text('Failed to dispatch: $e')));
                          }
                        } finally {
                          if (mounted) setState(() => _isCreatingDispatch = false);
                        }
                      }
                    },
                    child: const Text('DISPATCH'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      setState(() => _isCreatingDispatch = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteDispatch(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Dispatch'),
          content: const Text('Are you sure you want to cancel and delete this dispatch record?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final supabase = ref.read(supabaseClientProvider);
      setState(() => _isCreatingDispatch = true);
      try {
        await supabase.from('material_dispatches').delete().eq('id', id);
        _refreshAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete dispatch: $e')));
        }
      } finally {
        if (mounted) setState(() => _isCreatingDispatch = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final materialsAsync = ref.watch(siteMaterialsProvider(widget.customerId));
    final dispatchesAsync = ref.watch(customerDispatchesProvider(widget.customerId));
    final roleAsync = ref.watch(userRoleProvider);
    final isAdmin = roleAsync.value == 'admin' || roleAsync.value == 'office_staff';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Site Material & Dispatches', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.customerName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.blue),
            tooltip: 'Share Materials',
            onPressed: () async {
              final List<String> lines = [];
              lines.add("Customer: ${widget.customerName}");
              if (widget.pmSuryaGharApplicationId != null && widget.pmSuryaGharApplicationId!.isNotEmpty) {
                lines.add("PM Surya Ghar Application ID: ${widget.pmSuryaGharApplicationId}");
              }
              lines.add("\nMaterials:");
              
              final materials = materialsAsync.value ?? [];
              for (var m in materials) {
                final type = ((m['products'] as Map?)?['name'] ?? '') as String;
                final status = m['status'] as String? ?? 'Not Started';
                final requiredQty = m['required_quantity'] as int? ?? 0;
                final installedQty = m['installed_quantity'] as int? ?? 0;
                
                if (type == 'Generation Meter') {
                  lines.add("- $type: Status: $status");
                } else {
                  lines.add("- $type: Required: $requiredQty, Installed: $installedQty, Status: $status");
                }
              }
              
              final shareText = lines.join("\n");
              // Capture messenger before async gap
              final messenger = ScaffoldMessenger.of(context);
              try {
                await SharePlus.instance.share(ShareParams(text: shareText));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: shareText));
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Share sheet not supported. Copied to clipboard!')),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: _isCreatingDispatch
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  // --- Materials Header ---
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: Text(
                      'SITE MATERIALS',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey, letterSpacing: 0.5),
                    ),
                  ),

                  materialsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error loading materials: $e')),
                    data: (materials) {
                      if (materials.isEmpty) {
                        return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No materials found.')));
                      }
                      return Column(
                        children: materials.map((m) {
                          return _MaterialCard(
                            material: m,
                            isAdmin: isAdmin,
                            ref: ref,
                          );
                        }).toList(),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // --- Dispatches Header ---
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: Text(
                      'MATERIAL DISPATCHES',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey, letterSpacing: 0.5),
                    ),
                  ),

                  dispatchesAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error loading dispatches: $e')),
                    data: (dispatches) {
                      if (dispatches.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text('No dispatch activities yet.', style: TextStyle(color: Colors.grey)),
                          ),
                        );
                      }
                      return Column(
                        children: dispatches.map((d) {
                          final name = d['material_name'] ?? 'N/A';
                          final qty = d['quantity'] ?? 0;
                          final status = d['status'] ?? 'Pending';
                          final staffName = (d['staff'] as Map?)?['name'] ?? 'Unassigned';
                          final photoUrl = d['photo_url'] as String?;

                          Color statusColor = Colors.red;
                          if (status == 'Out for Delivery') statusColor = Colors.orange;
                          if (status == 'Delivered') statusColor = Colors.green;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text('$name × $qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('Delivery Staff: $staffName'),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Text('Status: '),
                                      Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  if (d['delivered_at'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text('Delivered: ${AppDateUtils.formatDateTime(d['delivered_at'])}', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ] else if (d['created_at'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text('Created: ${AppDateUtils.formatDateTime(d['created_at'])}', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                  ],
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (photoUrl != null)
                                    IconButton(
                                      icon: const Icon(Icons.image, color: Colors.blue),
                                      tooltip: 'View Delivery Photo',
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Delivery Photo'),
                                            content: Image.network(photoUrl),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('CLOSE'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  if (isAdmin)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      tooltip: 'Cancel Dispatch',
                                      onPressed: () => _deleteDispatch(d['id']),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateDispatchDialog,
              icon: const Icon(Icons.local_shipping),
              label: const Text('DISPATCH'),
            )
          : null,
    );
  }
}

class _MaterialCard extends StatefulWidget {
  final Map<String, dynamic> material;
  final bool isAdmin;
  final WidgetRef ref;

  const _MaterialCard({
    required this.material,
    required this.isAdmin,
    required this.ref,
  });

  @override
  State<_MaterialCard> createState() => _MaterialCardState();
}

class _MaterialCardState extends State<_MaterialCard> {
  bool _isExpanded = false;

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed':
      case 'Installed':
        return Colors.green;
      case 'In Progress':
        return Colors.orange;
      case 'Received':
        return Colors.blue;
      case 'Pending':
        return Colors.red;
      case 'Not Required':
        return Colors.grey;
      case 'Not Started':
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Completed':
      case 'Installed':
        return Icons.check_circle_outline;
      case 'In Progress':
        return Icons.play_circle_outline;
      case 'Received':
        return Icons.warehouse_outlined;
      case 'Pending':
        return Icons.error_outline;
      case 'Not Required':
        return Icons.block_outlined;
      case 'Not Started':
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = ((widget.material['products'] as Map?)?['name'] ?? '') as String;
    final requiredQty = widget.material['required_quantity'] as int? ?? 0;
    final installedQty = widget.material['installed_quantity'] as int? ?? 0;
    final status = widget.material['status'] as String? ?? 'Not Started';
    final serialNo = widget.material['serial_number'] as String?;
    final date = widget.material['updated_at'] as String?;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            title: Text(
              type,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                type == 'Generation Meter'
                    ? 'Status: $status'
                    : 'Installed: $installedQty of $requiredQty',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon(status), size: 14, color: _statusColor(status)),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (type != 'Generation Meter') ...[
                    _buildDetailRow('Required Quantity:', '$requiredQty'),
                    _buildDetailRow('Installed Quantity:', '$installedQty'),
                  ],
                  _buildDetailRow('Serial Number:', (serialNo != null && serialNo.isNotEmpty) ? serialNo : 'Not Set'),
                  _buildDetailRow('Last Updated:', (date != null && date.isNotEmpty) ? AppDateUtils.formatDateTime(date) : 'N/A'),
                  if (widget.isAdmin) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('EDIT MATERIAL DETAILS'),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (context) => EditMaterialSheet(
                              material: widget.material,
                              isAdmin: widget.isAdmin,
                              ref: widget.ref,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
