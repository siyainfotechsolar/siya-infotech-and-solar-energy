import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_utils.dart';
import '../providers/material_provider.dart';

class EditMaterialSheet extends StatefulWidget {
  final Map<String, dynamic> material;
  final bool isAdmin;
  final WidgetRef ref;

  const EditMaterialSheet({
    super.key,
    required this.material,
    required this.isAdmin,
    required this.ref,
  });

  @override
  State<EditMaterialSheet> createState() => _EditMaterialSheetState();
}

class _EditMaterialSheetState extends State<EditMaterialSheet> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _requiredQtyController;
  late TextEditingController _installedQtyController;
  late TextEditingController _remarksController;
  
  // Solar Panel fields
  late TextEditingController _panelBrandController;
  late TextEditingController _panelWattageController;
  
  // Inverter fields
  late TextEditingController _inverterBrandController;
  late TextEditingController _inverterCapacityController;
  
  // Generation Meter fields
  late TextEditingController _meterNumberController;
  DateTime? _meterInstallationDate;
  
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.material;
    
    _requiredQtyController = TextEditingController(text: '${m['required_quantity'] ?? 0}');
    _installedQtyController = TextEditingController(text: '${m['installed_quantity'] ?? 0}');
    _remarksController = TextEditingController(text: m['remarks'] ?? '');
    
    _panelBrandController = TextEditingController(text: m['panel_brand'] ?? '');
    _panelWattageController = TextEditingController(text: m['panel_wattage'] ?? '');
    
    _inverterBrandController = TextEditingController(text: m['inverter_brand'] ?? '');
    _inverterCapacityController = TextEditingController(text: m['inverter_capacity'] ?? '');
    
    _meterNumberController = TextEditingController(text: m['meter_number'] ?? '');
    
    if (m['meter_installation_date'] != null) {
      _meterInstallationDate = DateTime.tryParse(m['meter_installation_date'] as String);
    }
    
    _status = m['status'] as String? ?? 'Not Started';
  }

  @override
  void dispose() {
    _requiredQtyController.dispose();
    _installedQtyController.dispose();
    _remarksController.dispose();
    _panelBrandController.dispose();
    _panelWattageController.dispose();
    _inverterBrandController.dispose();
    _inverterCapacityController.dispose();
    _meterNumberController.dispose();
    super.dispose();
  }

  List<String> _getAvailableStatuses(String productName) {
    if (productName == 'Generation Meter') {
      return const ['Not Required', 'Pending', 'Received', 'Installed'];
    } else {
      return const ['Not Started', 'In Progress', 'Completed', 'Pending'];
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _meterInstallationDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _meterInstallationDate) {
      setState(() {
        _meterInstallationDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    
    final productName = ((widget.material['products'] as Map?)?['name'] ?? '') as String;
    final reqQty = int.tryParse(_requiredQtyController.text.trim()) ?? 0;
    final instQty = int.tryParse(_installedQtyController.text.trim()) ?? 0;
    
    final updates = <String, dynamic>{
      'installed_quantity': instQty,
      'status': _status,
      'remarks': _remarksController.text.trim(),
    };

    if (widget.isAdmin) {
      updates['required_quantity'] = reqQty;
      
      if (productName == 'Solar Panel') {
        updates['panel_brand'] = _panelBrandController.text.trim();
        updates['panel_wattage'] = _panelWattageController.text.trim();
      } else if (productName == 'Inverter') {
        updates['inverter_brand'] = _inverterBrandController.text.trim();
        updates['inverter_capacity'] = _inverterCapacityController.text.trim();
      } else if (productName == 'Generation Meter') {
        updates['meter_number'] = _meterNumberController.text.trim();
        updates['meter_installation_date'] = _meterInstallationDate?.toIso8601String().substring(0, 10);
      }
    }

    try {
      await updateSiteMaterial(
        ref: widget.ref,
        materialId: widget.material['id'] as String,
        customerId: widget.material['site_id'] as String,
        updates: updates,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productName = ((widget.material['products'] as Map?)?['name'] ?? '') as String;
    final statuses = _getAvailableStatuses(productName);
    
    // Ensure currently saved status is valid in the dropdown items list
    if (!statuses.contains(_status)) {
      _status = statuses.first;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Edit $productName',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (!widget.isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Staff Access',
                            style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Brand/Spec Info Cards for Staff (Read-Only)
                  if (!widget.isAdmin) ...[
                    _buildReadOnlySpecs(productName),
                    const SizedBox(height: 12),
                  ],

                  // Required Quantity
                  if (widget.isAdmin) ...[
                    if (productName != 'Generation Meter') ...[
                      TextFormField(
                        controller: _requiredQtyController,
                        decoration: const InputDecoration(
                          labelText: 'Required Quantity',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.shopping_bag_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter quantity';
                          final val = int.tryParse(value);
                          if (val == null || val < 0) return 'Enter valid positive number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],

                  // Installed Quantity
                  if (productName != 'Generation Meter') ...[
                    TextFormField(
                      controller: _installedQtyController,
                      decoration: const InputDecoration(
                        labelText: 'Installed / Used Quantity',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.check_circle_outline),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Enter installed quantity';
                        final val = int.tryParse(value);
                        if (val == null || val < 0) return 'Enter valid positive number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Product Specific Admin Fields
                  if (widget.isAdmin) ...[
                    if (productName == 'Solar Panel') ...[
                      TextFormField(
                        controller: _panelBrandController,
                        decoration: const InputDecoration(
                          labelText: 'Panel Brand',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.branding_watermark_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _panelWattageController,
                        decoration: const InputDecoration(
                          labelText: 'Panel Wattage (W)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.flash_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (productName == 'Inverter') ...[
                      TextFormField(
                        controller: _inverterBrandController,
                        decoration: const InputDecoration(
                          labelText: 'Inverter Brand',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.branding_watermark_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _inverterCapacityController,
                        decoration: const InputDecoration(
                          labelText: 'Capacity (e.g. 5kW)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.bolt_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (productName == 'Generation Meter') ...[
                      TextFormField(
                        controller: _meterNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Meter Number (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        leading: const Icon(Icons.calendar_month_outlined),
                        title: Text(
                          _meterInstallationDate == null
                              ? 'Installation Date (Optional)'
                              : 'Installed on: ${AppDateUtils.formatDate(_meterInstallationDate!.toIso8601String())}',
                          style: TextStyle(
                            color: _meterInstallationDate == null ? Colors.black54 : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_calendar_outlined),
                          onPressed: _selectDate,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],

                  // Status Dropdown
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.hourglass_empty_outlined),
                    ),
                    items: statuses.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _status = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Remarks
                  TextFormField(
                    controller: _remarksController,
                    decoration: const InputDecoration(
                      labelText: 'Remarks / Remarks',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.comment_bank_outlined),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save Changes', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReadOnlySpecs(String productName) {
    final m = widget.material;
    
    List<Widget> children = [];
    
    // Always show Required Qty for non-meter
    if (productName != 'Generation Meter') {
      children.add(_buildSpecRow('Required Quantity:', '${m['required_quantity'] ?? 0}'));
    }

    if (productName == 'Solar Panel') {
      final brand = m['panel_brand'] as String? ?? 'N/A';
      final watt = m['panel_wattage'] as String? ?? 'N/A';
      children.add(_buildSpecRow('Panel Brand:', brand));
      children.add(_buildSpecRow('Panel Wattage:', watt.isNotEmpty ? '$watt W' : 'N/A'));
    } else if (productName == 'Inverter') {
      final brand = m['inverter_brand'] as String? ?? 'N/A';
      final cap = m['inverter_capacity'] as String? ?? 'N/A';
      children.add(_buildSpecRow('Inverter Brand:', brand));
      children.add(_buildSpecRow('Capacity:', cap));
    } else if (productName == 'Generation Meter') {
      final meterNo = m['meter_number'] as String? ?? 'N/A';
      final date = m['meter_installation_date'] as String? ?? 'N/A';
      children.add(_buildSpecRow('Meter Number:', meterNo));
      children.add(_buildSpecRow('Installation Date:', date != 'N/A' ? AppDateUtils.formatDate(date) : 'N/A'));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Material Details (Managed by Admin)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
