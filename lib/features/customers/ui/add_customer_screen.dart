import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/date_utils.dart';
import 'customer_details_screen.dart';
import '../providers/customer_provider.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/services/global_loading_service.dart';
import '../../../core/localization/app_strings.dart';

class AddCustomerScreen extends ConsumerStatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  ConsumerState<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends ConsumerState<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _consumerNumberController = TextEditingController();
  final _villageController = TextEditingController();
  final _addressController = TextEditingController();
  final _remarksController = TextEditingController();
  final _pmSuryaGharApplicationIdController = TextEditingController();

  String? _selectedSystemSize;
  DateTime _applicationDate = DateTime.now();
  List<String> _villageOptions = [];
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;

  final List<String> _systemSizeOptions = ['1 kW', '2 kW', '3 kW', '4 kW', '5 kW', '10 kW', 'Other'];

  @override
  void initState() {
    super.initState();
    _fetchVillageSuggestions();
  }

  Future<void> _fetchVillageSuggestions() async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final res = await supabase.from('customers').select('village');
      final list = (res as List)
          .map((e) => e['village'] as String?)
          .whereType<String>()
          .where((v) => v.trim().isNotEmpty)
          .toSet()
          .toList();
      list.sort();
      if (mounted) {
        setState(() {
          _villageOptions = list;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _consumerNumberController.dispose();
    _villageController.dispose();
    _addressController.dispose();
    _remarksController.dispose();
    _pmSuryaGharApplicationIdController.dispose();
    super.dispose();
  }

  void _onFieldChanged(String _) {
    if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Are you sure you want to discard them?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('DISCARD', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _showDuplicateDialog(Map<String, dynamic> existingCustomer) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('CUSTOMER ALREADY EXISTS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(existingCustomer['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(existingCustomer['customer_id'] ?? ''),
            const SizedBox(height: 4),
            Text(existingCustomer['mobile'] ?? ''),
            if (existingCustomer['consumer_number'] != null) Text(existingCustomer['consumer_number']),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: existingCustomer)));
            },
            child: const Text('VIEW EXISTING'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = ref.read(supabaseClientProvider);
      
      // Duplicate Check: Mobile
      final duplicateMobile = await supabase
          .from('customers')
          .select('*')
          .eq('mobile', _mobileController.text.trim())
          .maybeSingle();
          
      if (duplicateMobile != null) {
        setState(() => _isLoading = false);
        await _showDuplicateDialog(duplicateMobile);
        return;
      }
      
      // Duplicate Check: Consumer Number
      final consumerNum = _consumerNumberController.text.trim();
      if (consumerNum.isNotEmpty) {
        final duplicateConsumer = await supabase
            .from('customers')
            .select('*')
            .eq('consumer_number', consumerNum)
            .maybeSingle();
            
        if (duplicateConsumer != null) {
          setState(() => _isLoading = false);
          await _showDuplicateDialog(duplicateConsumer);
          return;
        }
      }

      // Generate ID like C000001
      final countResp = await supabase.from('customers').select('id');
      final newIdNumber = (countResp as List).length + 1;
      final generatedId = 'C${newIdNumber.toString().padLeft(6, '0')}';

      final user = ref.read(currentUserProvider);

      final insertData = {
        'customer_id': generatedId,
        'name': _nameController.text.trim(),
        'mobile': _mobileController.text.trim(),
        'consumer_number': consumerNum.isEmpty ? null : consumerNum,
        'village': _villageController.text.trim(),
        'address': _addressController.text.trim(),
        'system_size': _selectedSystemSize,
        'application_date': _applicationDate.toIso8601String().split('T').first,
        'remarks': _remarksController.text.trim(),
        'pm_surya_ghar_application_id': _pmSuryaGharApplicationIdController.text.trim().isEmpty ? null : _pmSuryaGharApplicationIdController.text.trim(),
        'stage': 'PM Surya Ghar Application',
        'created_by': user?.id,
      };

      final insertedCustomer = await supabase.from('customers').insert(insertData).select().single();

      if (user != null) {
        try {
          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
          final staffName = staffNameRes?['name'] ?? 'Staff member';
          await ActivityLogger.log(
            supabase: supabase,
            customerId: insertedCustomer['id'],
            action: 'customer_added',
            description: '$staffName added customer ${insertedCustomer['name']}',
            performedBy: user.id,
          );
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer saved successfully!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        
        // Refresh provider to update lists and dashboard
        ref.invalidate(customerListProvider);
        
        // Navigate to Customer Details
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: insertedCustomer)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NEW CUSTOMER'),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Customer Name *', prefixIcon: Icon(Icons.person)),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                  onChanged: _onFieldChanged,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mobileController,
                  decoration: const InputDecoration(labelText: 'Mobile Number *', prefixIcon: Icon(Icons.phone)),
                  keyboardType: TextInputType.phone,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Required';
                    if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Enter a valid 10-digit mobile number';
                    return null;
                  },
                  onChanged: _onFieldChanged,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _consumerNumberController,
                  decoration: const InputDecoration(labelText: 'Consumer Number', prefixIcon: Icon(Icons.numbers)),
                  onChanged: _onFieldChanged,
                ),
                const SizedBox(height: 16),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    return _villageOptions.where((String option) {
                      return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    _villageController.text = selection;
                    _onFieldChanged(selection);
                  },
                  fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                    _villageController.text = controller.text;
                    controller.addListener(() {
                      if (_villageController.text != controller.text) {
                        _villageController.text = controller.text;
                        _onFieldChanged(controller.text);
                      }
                    });
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Village 🔍', prefixIcon: Icon(Icons.location_city)),
                      onEditingComplete: onEditingComplete,
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on)),
                  maxLines: 3,
                  onChanged: _onFieldChanged,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedSystemSize,
                  decoration: const InputDecoration(labelText: 'System Size', prefixIcon: Icon(Icons.solar_power)),
                  hint: const Text('Select kW ▼'),
                  items: _systemSizeOptions.map((size) => DropdownMenuItem(value: size, child: Text(size))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedSystemSize = val);
                    _onFieldChanged(val ?? '');
                  },
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _applicationDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _applicationDate = date);
                      _onFieldChanged('');
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Application Date', prefixIcon: Icon(Icons.calendar_today)),
                    child: Text(AppDateUtils.formatDate(_applicationDate.toIso8601String())),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pmSuryaGharApplicationIdController,
                  decoration: const InputDecoration(labelText: 'PM Surya Ghar Application ID', prefixIcon: Icon(Icons.confirmation_number_outlined)),
                  onChanged: _onFieldChanged,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _remarksController,
                  decoration: const InputDecoration(labelText: 'Remarks', prefixIcon: Icon(Icons.notes)),
                  maxLines: 2,
                  onChanged: _onFieldChanged,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveCustomer,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('SAVE CUSTOMER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
