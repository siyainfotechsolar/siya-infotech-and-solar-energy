import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/notifications/notification_state.dart';
import '../../../core/notifications/notification_model.dart';
import '../../../core/widgets/unsaved_changes_scope.dart';
import '../../../core/utils/mobile_validator.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/app_tap_widgets.dart';
import '../../customers/ui/customer_details_screen.dart';
import 'lead_details_screen.dart';

class AddLeadScreen extends ConsumerStatefulWidget {
  const AddLeadScreen({super.key});

  @override
  ConsumerState<AddLeadScreen> createState() => _AddLeadScreenState();
}

class _AddLeadScreenState extends ConsumerState<AddLeadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _remarksController = TextEditingController();
  
  String _source = 'Manual';
  DateTime? _followUpDate;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _showDuplicateCustomerDialog(Map<String, dynamic> customer) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('CUSTOMER ALREADY EXISTS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(customer['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('ID: ${customer['customer_id'] ?? ''}'),
            Text('Mobile: ${customer['mobile'] ?? ''}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)));
            },
            child: const Text('VIEW CUSTOMER'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDuplicateLeadDialog(Map<String, dynamic> lead) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('LEAD ALREADY EXISTS', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lead['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Lead ID: ${lead['lead_id'] ?? lead['id'] ?? ''}'),
            Text('Mobile: ${lead['mobile'] ?? ''}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LeadDetailsScreen(lead: lead)));
            },
            child: const Text('VIEW LEAD'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLead() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final supabase = ref.read(supabaseClientProvider);
      final cleanMobile = MobileValidator.normalize(_mobileController.text);
      
      // 1. Check duplicate Customer
      final existingCustomer = await MobileValidator.checkDuplicate(
        client: supabase,
        table: 'customers',
        mobile: cleanMobile,
      );

      if (existingCustomer != null) {
        setState(() => _isLoading = false);
        if (mounted) await _showDuplicateCustomerDialog(existingCustomer);
        return;
      }

      // 2. Check duplicate Lead
      final existingLead = await MobileValidator.checkDuplicate(
        client: supabase,
        table: 'leads',
        mobile: cleanMobile,
      );

      if (existingLead != null) {
        setState(() => _isLoading = false);
        if (mounted) await _showDuplicateLeadDialog(existingLead);
        return;
      }

      // 3. Generate Unique Lead ID: LEAD-000001
      final countResp = await supabase.from('leads').select('id');
      final newIdNumber = (countResp as List).length + 1;
      final generatedLeadId = 'LEAD-${newIdNumber.toString().padLeft(6, '0')}';
      
      final user = ref.read(currentUserProvider);

      final insertedLead = await supabase.from('leads').insert({
        'lead_id': generatedLeadId,
        'name': _nameController.text.trim(),
        'mobile': cleanMobile,
        'village': _cityController.text.trim(),
        'address': _addressController.text.trim(),
        'remarks': _remarksController.text.trim(),
        'source': _source,
        'status': 'new',
        'follow_up_date': _followUpDate?.toIso8601String().split('T').first,
        'created_by': user?.id,
      }).select().single();
      
      try {
        final notificationRepo = ref.read(notificationRepositoryProvider);
        await notificationRepo.notifyAdmins(
          notificationType: NotificationType.leadCreated,
          title: '🎯 New Lead Added',
          message: 'New lead ${insertedLead['name']} ($generatedLeadId) has been created.',
          relatedRecordId: insertedLead['id'],
        );
      } catch (_) {}
      
      if (mounted) {
        AppFeedback.showSuccess(context, 'Lead $generatedLeadId created successfully! ✓');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, 'Error saving lead: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isDirty =>
      _nameController.text.isNotEmpty ||
      _mobileController.text.isNotEmpty ||
      _cityController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesScope(
      isDirty: _isDirty,
      child: Scaffold(
        appBar: AppBar(title: const Text('NEW REGISTRATION (LEAD)')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Every new registration starts as a Lead. Once qualified, convert to Customer.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person)),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mobileController,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number *',
                    prefixIcon: Icon(Icons.phone),
                    prefixText: '+91 ',
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: MobileValidator.inputFormatters,
                  validator: (val) => MobileValidator.validate(val, required: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'City / Village', prefixIcon: Icon(Icons.location_city)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.home)),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _source,
                  decoration: const InputDecoration(labelText: 'Lead Source', prefixIcon: Icon(Icons.source)),
                  items: const [
                    DropdownMenuItem(value: 'Manual', child: Text('Manual')),
                    DropdownMenuItem(value: 'WhatsApp', child: Text('WhatsApp')),
                    DropdownMenuItem(value: 'Call', child: Text('Call')),
                    DropdownMenuItem(value: 'Reference', child: Text('Reference')),
                    DropdownMenuItem(value: 'Import', child: Text('Import')),
                  ],
                  onChanged: (val) => setState(() => _source = val!),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setState(() => _followUpDate = date);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Follow-up Date', prefixIcon: Icon(Icons.calendar_today)),
                    child: Text(_followUpDate != null ? AppDateUtils.formatDate(_followUpDate!.toIso8601String()) : 'Select Date (Optional)'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarksController,
                  decoration: const InputDecoration(labelText: 'Remarks / Notes', prefixIcon: Icon(Icons.notes)),
                  maxLines: 2,
                ),
                const SizedBox(height: 32),
                AppButton(
                  label: 'CREATE LEAD',
                  isLoading: _isLoading,
                  icon: Icons.person_add_alt_1,
                  onPressed: _saveLead,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
