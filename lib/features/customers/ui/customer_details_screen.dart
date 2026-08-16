import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/stage_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../../tasks/ui/add_task_screen.dart';
import '../../tasks/ui/task_details_screen.dart';
import '../../materials/providers/material_provider.dart';
import '../../materials/ui/site_material_screen.dart';
import '../providers/customer_provider.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/utils/activity_logger.dart';
import 'widgets/customer_admin_photos_widget.dart';



class CustomerDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  ConsumerState<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends ConsumerState<CustomerDetailsScreen> {
  late String _currentStage;
  bool _isAdvancing = false;
  bool? _loanRequired;
  late Map<String, dynamic> _customerData;
  Map<String, String>? _installationStatuses;
  final Map<String, PlatformFile?> _installerPickedPhotos = {};

  @override
  void initState() {
    super.initState();
    _customerData = Map<String, dynamic>.from(widget.customer);
    _currentStage = _customerData['stage'] ?? 'Lead';
    _loanRequired = _customerData['loan_required'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(activeCustomerIdProvider.notifier).update(_customerData['id']);
    });
  }

  Future<void> _updateLoanRequired(bool? val) async {
    if (val == null) return;
    setState(() {
      _loanRequired = val;
    });
    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.from('customers').update({'loan_required': val}).eq('id', _customerData['id']);
      
      final user = ref.read(currentUserProvider);
      if (user != null) {
        try {
          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
          final staffName = staffNameRes?['name'] ?? 'Staff member';
          await ActivityLogger.log(
            supabase: supabase,
            customerId: _customerData['id'],
            action: 'customer_updated',
            description: '$staffName updated customer loan requirement to ${val == true ? "Yes" : "No"}',
            performedBy: user.id,
          );
        } catch (_) {}
      }

      ref.invalidate(customerListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating loan selection: $e')));
    }
  }

  @override
  void dispose() {
    ref.read(activeCustomerIdProvider.notifier).update(null);
    super.dispose();
  }

  Future<void> _callCustomer() async {
    final mobile = _customerData['mobile'];
    if (mobile == null) return;
    final Uri url = Uri(scheme: 'tel', path: mobile);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch dialer')));
    }
  }

  Future<void> _whatsappCustomer() async {
    final mobile = _customerData['mobile'];
    final name = _customerData['name'];
    if (mobile == null) return;
    final Uri url = Uri.parse('https://wa.me/91$mobile?text=Hello $name, regarding your Solar CRM application...');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch WhatsApp')));
    }
  }

  Future<void> _advanceStage() async {
    if (_currentStage == 'PM Surya Ghar Application' && _loanRequired == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select whether a loan is required.')),
      );
      return;
    }

    if (_currentStage == 'Installation') {
      final tasksAsync = ref.read(installationTasksProvider(_customerData['id']));
      final tasks = tasksAsync.value ?? [];
      
      if (tasks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Installation progress has not been initialized.')),
        );
        return;
      }
      
      final allCompleted = tasks.every((t) => t['status'] == 'Completed');
      if (!allCompleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All installation tasks (Structure, Panels, and Wiring) must be Completed before advancing.'),
          ),
        );
        return;
      }
    }

    final nextStage = StageConfig.nextStage(_currentStage, loanRequired: _loanRequired ?? false);
    if (nextStage == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Advance Stage?'),
        content: Text('Are you sure you want to advance to $nextStage?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('ADVANCE')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isAdvancing = true);

    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);

      await supabase.rpc('advance_customer_stage', params: {
        'p_customer_id': _customerData['id'],
        'p_old_stage': _currentStage,
        'p_new_stage': nextStage,
        'p_changed_by': user?.id,
      });

      setState(() => _currentStage = nextStage);
      
      // Refresh providers
      ref.invalidate(customerHistoryProvider(_customerData['id']));
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stage updated successfully!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating stage: $e')));
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

  Future<void> _showEditDetailsDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: _customerData['name']);
    final mobileCtrl = TextEditingController(text: _customerData['mobile']);
    final consumerCtrl = TextEditingController(text: _customerData['consumer_number']);
    final villageCtrl = TextEditingController(text: _customerData['village']);
    final addressCtrl = TextEditingController(text: _customerData['address']);
    final remarksCtrl = TextEditingController(text: _customerData['remarks']);
    final pmAppIdCtrl = TextEditingController(text: _customerData['pm_surya_ghar_application_id']);
    final referenceCtrl = TextEditingController(text: _customerData['reference']);
    String? selectedSize = _customerData['system_size'];

    final List<String> systemSizes = ['1 kW', '2 kW', '3 kW', '4 kW', '5 kW', '10 kW', 'Other'];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Customer Details', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Customer Name *'),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: mobileCtrl,
                        decoration: const InputDecoration(labelText: 'Mobile Number *'),
                        keyboardType: TextInputType.phone,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Required';
                          if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Enter valid 10-digit number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: consumerCtrl,
                        decoration: const InputDecoration(labelText: 'Consumer Number'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: villageCtrl,
                        decoration: const InputDecoration(labelText: 'Village'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(labelText: 'Address'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: systemSizes.contains(selectedSize) ? selectedSize : null,
                        decoration: const InputDecoration(labelText: 'System Size'),
                        items: systemSizes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) => setDialogState(() => selectedSize = val),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: pmAppIdCtrl,
                        decoration: const InputDecoration(labelText: 'PM Surya Ghar Application ID'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: referenceCtrl,
                        decoration: const InputDecoration(labelText: 'Reference'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: remarksCtrl,
                        decoration: const InputDecoration(labelText: 'Remarks'),
                        maxLines: 2,
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
                      Navigator.pop(context); // Close edit dialog
                      
                      // Show loading dialog
                      showDialog(
                        context: this.context,
                        barrierDismissible: false,
                        builder: (ctx) => const Center(child: CircularProgressIndicator()),
                      );

                      try {
                        final supabase = ref.read(supabaseClientProvider);
                        final user = ref.read(currentUserProvider);

                        final updateData = {
                          'name': nameCtrl.text.trim(),
                          'mobile': mobileCtrl.text.trim(),
                          'consumer_number': consumerCtrl.text.trim().isEmpty ? null : consumerCtrl.text.trim(),
                          'village': villageCtrl.text.trim().isEmpty ? null : villageCtrl.text.trim(),
                          'address': addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                          'system_size': selectedSize,
                          'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
                          'pm_surya_ghar_application_id': pmAppIdCtrl.text.trim().isEmpty ? null : pmAppIdCtrl.text.trim(),
                          'reference': referenceCtrl.text.trim().isEmpty ? null : referenceCtrl.text.trim(),
                        };

                        await supabase.from('customers').update(updateData).eq('id', _customerData['id']);

                        if (user != null) {
                          try {
                            final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
                            final staffName = staffNameRes?['name'] ?? 'Staff member';
                            await ActivityLogger.log(
                              supabase: supabase,
                              customerId: _customerData['id'],
                              action: 'customer_updated',
                              description: '$staffName edited customer details',
                              performedBy: user.id,
                            );
                          } catch (_) {}
                        }

                        // Fetch updated details
                        final updated = await supabase
                            .from('customers')
                            .select('*, site_installation_tasks(task_type, status)')
                            .eq('id', _customerData['id'])
                            .single();

                        if (mounted) {
                          Navigator.pop(this.context); // Close loading dialog
                          setState(() {
                            _customerData = updated;
                          });
                          ref.invalidate(customerListProvider);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('Details updated successfully!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Navigator.pop(this.context); // Close loading dialog
                          ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Error updating details: $e')));
                        }
                      }
                    }
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customerData;
    final historyAsync = ref.watch(customerHistoryProvider(customer['id']));
    final tasksAsync = ref.watch(customerTasksProvider(customer['id']));
    final roleAsync = ref.watch(userRoleProvider);
    final creatorAsync = ref.watch(creatorNameProvider(customer['created_by']));

    return Scaffold(
      appBar: AppBar(
        title: Text(customer['name'] ?? 'Customer Details'),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: _callCustomer),
          IconButton(icon: const Icon(Icons.message, color: Colors.green), onPressed: _whatsappCustomer),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.blue),
            tooltip: 'Share',
            onPressed: () async {
              final String name = customer['name'] ?? 'N/A';
              final String mobile = customer['mobile'] ?? 'N/A';
              final String consumerNo = customer['consumer_number'] ?? 'N/A';
              final String pmAppId = customer['pm_surya_ghar_application_id'] ?? 'N/A';
              final String stage = customer['stage'] ?? 'Lead';
              
              String shareText = "";
              
              if (stage == 'Installation') {
                final tasksAsync = ref.read(installationTasksProvider(customer['id']));
                final tasks = tasksAsync.value ?? [];
                
                final structure = tasks.firstWhere((t) => t['task_type'] == 'Structure Installation', orElse: () => <String, dynamic>{});
                final panel = tasks.firstWhere((t) => t['task_type'] == 'Panel Uploading', orElse: () => <String, dynamic>{});
                final wiring = tasks.firstWhere((t) => t['task_type'] == 'Wiring', orElse: () => <String, dynamic>{});
                
                final strStatus = structure['status'] ?? 'Pending';
                final panStatus = panel['status'] ?? 'Pending';
                final wirStatus = wiring['status'] ?? 'Pending';
                
                final bool allCompleted = tasks.isNotEmpty && tasks.every((t) => t['status'] == 'Completed');
                final bool anyInProgress = tasks.any((t) => t['status'] == 'In Progress' || t['status'] == 'Completed');
                final String instStatus = allCompleted ? 'Completed' : (anyInProgress ? 'In Progress' : 'Pending');
                
                shareText = "Customer Name: $name\n"
                    "PM Surya Ghar Application ID: $pmAppId\n"
                    "Installation Status: $instStatus\n"
                    "Structure Status: $strStatus\n"
                    "Panel Status: $panStatus\n"
                    "Wiring Status: $wirStatus";
              } else if (stage == 'Loan Processing') {
                final String loanReq = customer['loan_required'] == true ? 'Yes' : (customer['loan_required'] == false ? 'No' : 'N/A');
                shareText = "Customer: $name\n"
                    "PM Surya Ghar Application ID: $pmAppId\n"
                    "Loan Required: $loanReq\n"
                    "Stage: $stage";
              } else if (stage == 'RTS') {
                final String reference = customer['reference'] ?? 'N/A';
                shareText = "Customer: $name\n"
                    "PM Surya Ghar Application ID: $pmAppId\n"
                    "RTS Status: In Progress\n"
                    "Reference Number: $reference\n"
                    "Status: Active";
              } else if (stage == 'Subsidy') {
                final String remarks = customer['remarks'] ?? 'No remarks';
                shareText = "Customer: $name\n"
                    "PM Surya Ghar Application ID: $pmAppId\n"
                    "Subsidy Status: In Progress\n"
                    "Status: $remarks";
              } else {
                shareText = "Customer Name: $name\n"
                    "Mobile: $mobile\n"
                    "Consumer Number: $consumerNo\n"
                    "PM Surya Ghar Application ID: $pmAppId\n"
                    "Current Stage: $stage";
              }
              
              try {
                await SharePlus.instance.share(ShareParams(text: shareText));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: shareText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share sheet not supported. Copied to clipboard!')),
                  );
                }
              }
            },
          ),
          roleAsync.when(
            data: (role) {
              if (role == 'admin' || role == 'office_staff') {
                return IconButton(
                  icon: const Icon(Icons.edit_note, color: Colors.blue),
                  tooltip: 'Edit Details',
                  onPressed: _showEditDetailsDialog,
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: roleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (role) {
          if (role == 'installer') {
            return _buildInstallerCustomerDetails(context, customer);
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            // --- Customer Info Card ---
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ID: ${customer['customer_id']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (customer['priority'] == true)
                          const Icon(Icons.star, color: Colors.amber),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Mobile: ${customer['mobile']}'),
                    Text('Consumer No: ${customer['consumer_number'] ?? 'N/A'}'),
                    Text('Village: ${customer['village'] ?? 'N/A'}'),
                    Text('Address: ${customer['address'] ?? 'N/A'}'),
                    Text('System Size: ${customer['system_size'] ?? 'N/A'}'),
                    Text('Application Date: ${AppDateUtils.formatDate(customer['application_date'])} (${AppDateUtils.applicationAgeLabel(customer['application_date'])})'),
                    Text('PM Surya Ghar Application ID: ${customer['pm_surya_ghar_application_id'] ?? 'N/A'}'),
                    if (customer['reference'] != null && customer['reference'].toString().isNotEmpty)
                      Text('Reference: ${customer['reference']}'),
                    if (customer['remarks'] != null && customer['remarks'].toString().isNotEmpty)
                      Text('Remarks: ${customer['remarks']}'),
                    creatorAsync.when(
                      data: (name) => name != null ? Text('Created By: $name') : const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    if (_currentStage == 'PM Surya Ghar Application') ...[
                      const SizedBox(height: 12),
                      const Text('Loan Required?', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Radio<bool>(
                            value: true,
                            groupValue: _loanRequired,
                            onChanged: _updateLoanRequired,
                          ),
                          const Text('Yes'),
                          const SizedBox(width: 24),
                          Radio<bool>(
                            value: false,
                            groupValue: _loanRequired,
                            onChanged: _updateLoanRequired,
                          ),
                          const Text('No'),
                        ],
                      ),
                    ] else if (_loanRequired != null) ...[
                      const SizedBox(height: 4),
                      Text('Loan Required: ${_loanRequired == true ? "Yes" : "No"}'),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Chip(
                          label: Text(_currentStage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          backgroundColor: StageConfig.stageColor(_currentStage),
                        ),
                        if (!StageConfig.isCompleted(_currentStage))
                          ElevatedButton.icon(
                            onPressed: _isAdvancing ? null : _advanceStage,
                            icon: _isAdvancing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_forward),
                            label: const Text('NEXT STAGE'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_currentStage == 'Installation') ...[
              _buildInstallationProgressSection(),
              const SizedBox(height: 16),
            ],

             // --- Site Material Summary Card ---
            _MaterialSummaryCard(
              customerId: customer['id'],
              customerName: customer['name'] ?? '',
              pmSuryaGharApplicationId: customer['pm_surya_ghar_application_id'],
            ),
            const SizedBox(height: 16),

            // --- Tasks Section ---
            const Text('Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) return const Text('No tasks for this customer.', style: TextStyle(color: Colors.grey));
                return Column(
                  children: tasks.map((task) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(task['name']),
                      subtitle: Text('Priority: ${(task['priority'] ?? 'normal').toUpperCase()}'),
                      trailing: _TaskStatusBadge(status: task['status']),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskDetailsScreen(task: task),
                          ),
                        );
                      },
                    ),
                  )).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading tasks: $e'),
            ),

            const SizedBox(height: 24),
            
            // --- Customer Installation & Electrical Photos ---
            CustomerAdminPhotosWidget(customerId: _customerData['id']),
            const SizedBox(height: 24),

            // --- Stage History Section ---
            const Text('Stage History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            historyAsync.when(
              data: (history) {
                if (history.isEmpty) return const Text('No history available.', style: TextStyle(color: Colors.grey));
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final h = history[index];
                    final staff = h['staff'] as Map<String, dynamic>?;
                    final staffName = staff?['name'] ?? 'Unknown';
                    final photoUrl = staff?['profile_photo_url'] as String?;
                    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
                    
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                        backgroundColor: hasPhoto ? Colors.transparent : Colors.blue.shade50,
                        child: hasPhoto
                            ? null
                            : const Icon(Icons.history, size: 18, color: Colors.blue),
                      ),
                      title: Text('Advanced to ${h['new_stage']}'),
                      subtitle: Text('By $staffName on ${AppDateUtils.formatDateTime(h['created_at'])}'),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading history: $e'),
            ),
          ],
        ),
      );
    },
  ),
      floatingActionButton: roleAsync.when(
        data: (role) {
          if (role != null && role != 'installer') {
            return FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AddTaskScreen(initialCustomerId: customer['id']),
                ));
              },
              tooltip: 'Add Task',
              child: const Icon(Icons.add_task),
            );
          }
          return null; // Return null to hide the FAB completely for installers or non-staff
        },
        loading: () => null,
        error: (_, __) => null,
      ),
    );
  }

  Widget _buildInstallationProgressSection() {
    final tasksAsync = ref.watch(installationTasksProvider(_customerData['id']));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'INSTALLATION PROGRESS',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(height: 12),
            tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return const Text('No installation tasks found.');
                }
                return Column(
                  children: tasks.map((task) => _buildInstallationTaskItem(task)).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading installation progress: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallationTaskItem(Map<String, dynamic> task) {
    final type = task['task_type'] as String;
    final status = task['status'] as String;
    final double pct = status == 'Completed' ? 1.0 : (status == 'In Progress' ? 0.5 : 0.0);
    final Color color = status == 'Completed' ? Colors.green : (status == 'In Progress' ? Colors.orange : Colors.grey);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: () => _showUpdateTaskStatusDialog(task),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    type,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    '${(pct * 100).toInt()}%',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              if (task['remark'] != null && (task['remark'] as String).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Remark: ${task['remark']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showUpdateTaskStatusDialog(Map<String, dynamic> task) {
    final type = task['task_type'] as String;
    String selectedStatus = task['status'] as String;
    final remarkController = TextEditingController(text: task['remark'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Update $type'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Status:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    items: const [
                      DropdownMenuItem(value: 'Not Started', child: Text('Not Started')),
                      DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                      DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedStatus = val;
                        });
                      }
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Remark:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarkController,
                    decoration: const InputDecoration(
                      hintText: 'Enter completion/progress remarks...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _updateInstallationTask(task['id'], selectedStatus, remarkController.text.trim());
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateInstallationTask(String id, String status, String remark) async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);
      
      final Map<String, dynamic> updateData = {
        'status': status,
        'remark': remark.isEmpty ? null : remark,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      
      if (status == 'Completed') {
        updateData['completed_by'] = user?.id;
        updateData['completed_at'] = DateTime.now().toUtc().toIso8601String();
      } else if (status == 'In Progress') {
        updateData['started_by'] = user?.id;
        updateData['started_at'] = DateTime.now().toUtc().toIso8601String();
      }
      
      await supabase.from('site_installation_tasks').update(updateData).eq('id', id);

      if (user != null) {
        try {
          final tasks = ref.read(installationTasksProvider(widget.customer['id'])).value ?? [];
          final task = tasks.firstWhere((t) => t['id'] == id);
          final taskType = task['task_type'] ?? 'Installation Task';
          
          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
          final staffName = staffNameRes?['name'] ?? 'Staff member';
          await ActivityLogger.log(
            supabase: supabase,
            customerId: widget.customer['id'],
            action: 'sub_stage_updated',
            description: '$staffName updated $taskType to $status',
            performedBy: user.id,
          );
        } catch (_) {}
      }
      
      ref.invalidate(installationTasksProvider(widget.customer['id']));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Installation sub-stage updated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Widget _buildInstallerCustomerDetails(BuildContext context, Map<String, dynamic> customer) {
    final tasksAsync = ref.watch(customerTasksProvider(customer['id']));
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer['name'] ?? 'N/A',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow('Mobile:', customer['mobile'] ?? 'N/A'),
                  _buildDetailRow('Address:', customer['address'] ?? 'N/A'),
                  _buildDetailRow('Village:', customer['village'] ?? 'N/A'),
                  _buildDetailRow('Consumer Number:', customer['consumer_number'] ?? 'N/A'),
                  _buildDetailRow('PM Surya Ghar App ID:', customer['pm_surya_ghar_application_id'] ?? 'N/A'),
                  _buildDetailRow('Current Stage:', customer['stage'] ?? 'Lead'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (customer['stage'] == 'Installation') ...[
            _buildInstallerInstallationSection(customer['id']),
            const SizedBox(height: 16),
          ],

          _MaterialSummaryCard(
            customerId: customer['id'],
            customerName: customer['name'] ?? '',
            pmSuryaGharApplicationId: customer['pm_surya_ghar_application_id'],
          ),
          const SizedBox(height: 16),

          const Text('Assigned Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          tasksAsync.when(
            data: (tasks) {
              if (tasks.isEmpty) {
                return const Text('No tasks for this customer.', style: TextStyle(color: Colors.grey));
              }
              return Column(
                children: tasks.map((task) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(task['name'] ?? 'Unknown Task'),
                      subtitle: Text('Priority: ${(task['priority'] ?? 'normal').toUpperCase()}'),
                      trailing: _TaskStatusBadge(status: task['status']),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskDetailsScreen(task: task),
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error loading tasks: $e'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallerInstallationSection(String customerId) {
    final tasksAsync = ref.watch(installationTasksProvider(customerId));

    return tasksAsync.when(
      loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e'),
      data: (tasks) {
        if (_installationStatuses == null) {
          _installationStatuses = {};
          for (var t in tasks) {
            final type = t['task_type'] as String;
            final status = t['status'] as String? ?? 'Not Started';
            _installationStatuses![type] = status;
          }
          final types = ['Structure Installation', 'Panel Uploading', 'Wiring', 'Inverter', 'Generation Meter'];
          for (var type in types) {
            if (!_installationStatuses!.containsKey(type)) {
              _installationStatuses![type] = 'Not Started';
            }
          }
        }

        final types = [
          {'key': 'Structure Installation', 'label': 'Structure'},
          {'key': 'Panel Uploading', 'label': 'Panel'},
          {'key': 'Wiring', 'label': 'Wiring'},
          {'key': 'Inverter', 'label': 'Inverter'},
          {'key': 'Generation Meter', 'label': 'Generation Meter'},
        ];

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'INSTALLATION STATUS',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1),
                ),
                const SizedBox(height: 12),
                ...types.map((typeObj) {
                  final key = typeObj['key']!;
                  final label = typeObj['label']!;
                  final currentStatus = _installationStatuses![key] ?? 'Not Started';
                  
                  final dbTask = tasks.firstWhere((t) => t['task_type'] == key, orElse: () => <String, dynamic>{});
                  final dbPhotoUrl = dbTask['photo_url'] as String?;
                  final pickedPhoto = _installerPickedPhotos[key];
                  final hasPhoto = (dbPhotoUrl != null && dbPhotoUrl.isNotEmpty) || pickedPhoto != null;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: currentStatus == 'Pending' ? 'Not Started' : currentStatus,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Not Started', child: Text('Pending')),
                              DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                              DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _installationStatuses![key] = val;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            hasPhoto ? Icons.photo_library : Icons.add_a_photo,
                            color: hasPhoto ? Colors.green : Colors.blue,
                          ),
                          onPressed: () async {
                            try {
                              final result = await FilePicker.pickFiles(
                                type: FileType.image,
                                withData: true,
                              );
                              if (result != null && result.files.isNotEmpty) {
                                setState(() {
                                  _installerPickedPhotos[key] = result.files.first;
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Photo selected for $label!')),
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error picking photo: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isAdvancing ? null : () => _saveInstallerInstallation(customerId, tasks),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isAdvancing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveInstallerInstallation(String customerId, List<Map<String, dynamic>> dbTasks) async {
    setState(() => _isAdvancing = true);
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);

    try {
      for (final key in _installationStatuses!.keys) {
        final status = _installationStatuses![key]!;
        
        final dbTask = dbTasks.firstWhere((t) => t['task_type'] == key, orElse: () => <String, dynamic>{});
        final taskId = dbTask['id'] as String?;
        final pickedPhoto = _installerPickedPhotos[key];
        
        String? finalPhotoUrl = dbTask['photo_url'] as String?;
        
        if (pickedPhoto != null && pickedPhoto.bytes != null) {
          final safeName = pickedPhoto.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
          final uploadPath = '$customerId/installation_${key.replaceAll(" ", "_")}_${DateTime.now().millisecondsSinceEpoch}_$safeName';

          await supabase.storage.from('task_attachments').uploadBinary(
            uploadPath,
            pickedPhoto.bytes!,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

          finalPhotoUrl = supabase.storage.from('task_attachments').getPublicUrl(uploadPath);
        }

        final Map<String, dynamic> updateData = {
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'photo_url': finalPhotoUrl,
        };

        if (status == 'Completed') {
          updateData['completed_by'] = user?.id;
          updateData['completed_at'] = DateTime.now().toUtc().toIso8601String();
        } else if (status == 'In Progress') {
          updateData['started_by'] = user?.id;
          updateData['started_at'] = DateTime.now().toUtc().toIso8601String();
        }

        if (taskId != null) {
          await supabase.from('site_installation_tasks').update(updateData).eq('id', taskId);
        } else {
          await supabase.from('site_installation_tasks').insert({
            'customer_id': customerId,
            'task_type': key,
            ...updateData,
          });
        }
      }

      if (user != null) {
        try {
          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
          final staffName = staffNameRes?['name'] ?? 'Staff member';
          await ActivityLogger.log(
            supabase: supabase,
            customerId: customerId,
            action: 'installation_updated',
            description: '$staffName updated installation sub-stages',
            performedBy: user.id,
          );
        } catch (_) {}
      }

      ref.invalidate(installationTasksProvider(customerId));
      _installerPickedPhotos.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Installation progress saved successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving progress: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }
}

class _TaskStatusBadge extends StatelessWidget {
  final String status;
  const _TaskStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'completed': c = Colors.green; break;
      case 'in_progress': c = Colors.blue; break;
      default: c = Colors.orange; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(status.toUpperCase(), style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Material Summary Card ────────────────────────────────────────────────────
class _MaterialSummaryCard extends ConsumerWidget {
  final String customerId;
  final String customerName;
  final String? pmSuryaGharApplicationId;

  const _MaterialSummaryCard({
    required this.customerId,
    required this.customerName,
    this.pmSuryaGharApplicationId,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed':
      case 'Installed':
        return Colors.green;
      case 'In Progress':
      case 'Received':
        return Colors.orange.shade700;
      case 'Pending':
        return Colors.red;
      case 'Not Required':
      default:
        return Colors.grey;
    }
  }

  String _summaryLabel(Map<String, dynamic> m) {
    final type = ((m['products'] as Map?)?['name'] ?? '') as String;
    final status = m['status'] as String? ?? 'Pending';
    final req = m['required_quantity'] as int? ?? 0;
    final inst = m['installed_quantity'] as int? ?? 0;

    if (type == 'Generation Meter') {
      return status;
    }
    
    final qtyStr = '$inst/$req';
    if (status == 'Completed' || status == 'Installed') {
      return '$qtyStr ✓';
    } else if (status == 'In Progress' || status == 'Received') {
      return '$qtyStr 🟡';
    } else {
      return '$qtyStr 🔴';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialsAsync = ref.watch(siteMaterialsProvider(customerId));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SITE MATERIAL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SiteMaterialScreen(
                      customerId: customerId,
                      customerName: customerName,
                      pmSuryaGharApplicationId: pmSuryaGharApplicationId,
                    ),
                  )),
                  icon: const Icon(Icons.inventory_2_outlined, size: 14),
                  label: const Text('VIEW', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
              ],
            ),
            const Divider(height: 12),
            materialsAsync.when(
              loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (_, __) => const Text('Error loading materials', style: TextStyle(color: Colors.red, fontSize: 12)),
              data: (materials) {
                return Column(
                  children: materials.map((m) {
                    final type = ((m['products'] as Map?)?['name'] ?? '') as String;
                    final status = m['status'] as String? ?? 'Pending';
                    final label = _summaryLabel(m);
                    final color = _statusColor(status);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 150, child: Text(type, style: const TextStyle(fontSize: 13))),
                          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
