import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import '../../auth/providers/auth_provider.dart';
import '../../customers/providers/customer_provider.dart';

// Model for parsed rows in preview stage
class PreviewRow {
  final int originalIndex;
  Map<String, String> data; // System Field Key -> Value
  String? error;
  bool isDuplicate;

  PreviewRow({
    required this.originalIndex,
    required this.data,
    this.error,
    this.isDuplicate = false,
  });
}

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  int _currentStep = 0; // 0 = File select, 1 = Column mapping, 2 = Preview & Edit
  List<List<dynamic>> _rawData = [];
  List<String> _headers = [];
  String? _fileName;
  bool _isLoading = false;

  // System Fields Definition
  final List<Map<String, dynamic>> _systemFields = [
    {'key': 'name', 'label': 'Customer Name', 'required': true},
    {'key': 'mobile', 'label': 'Mobile', 'required': true},
    {'key': 'consumer_number', 'label': 'Consumer Number', 'required': false},
    {'key': 'address', 'label': 'Address', 'required': false},
    {'key': 'village', 'label': 'Village', 'required': false},
    {'key': 'system_size', 'label': 'Requirement (System Size)', 'required': false},
    {'key': 'loan_required', 'label': 'Loan Required (Yes/No)', 'required': false},
    {'key': 'stage', 'label': 'Application Stage', 'required': false},
    {'key': 'application_date', 'label': 'Application Date', 'required': false},
    {'key': 'pm_surya_ghar_application_id', 'label': 'PM Surya Ghar Application ID', 'required': false},
    {'key': 'reference', 'label': 'Reference', 'required': false},
    {'key': 'remarks', 'label': 'Remarks', 'required': false},
  ];

  // Map of System Field Key -> CSV Column Index (e.g. {'name': 0, 'mobile': 1})
  final Map<String, int> _mappings = {};

  // Valid Standard CRM Stages List
  final List<String> _validStages = [
    'Lead',
    'PM Surya Ghar Application',
    'Loan Processing',
    'Installation',
    'RTS',
    'Subsidy',
    'Completed',
  ];


  // Preview List
  List<PreviewRow> _previewRows = [];

  // File Picker
  Future<void> _pickFile() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final extension = result.files.single.extension?.toLowerCase();
        _fileName = result.files.single.name;

        List<List<dynamic>> rows = [];
        if (extension == 'csv') {
          final input = String.fromCharCodes(fileBytes);
          final codec = Csv();
          rows = codec.decode(input);
        } else if (extension == 'xlsx') {
          final excel = Excel.decodeBytes(fileBytes);
          final sheet = excel.tables.keys.first;
          final excelRows = excel.tables[sheet]?.rows ?? [];
          rows = excelRows.map((r) => r.map((c) => c?.value?.toString() ?? '').toList()).toList();
        }

        if (rows.isEmpty) {
          throw Exception('The uploaded file is empty.');
        }

        setState(() {
          _rawData = rows;
          _headers = rows.first.map((e) => e.toString().trim()).toList();
          _currentStep = 1; // Go to Column Mapping step
          _autoMap();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error parsing file: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Pre-populate mapping based on keyword matches
  void _autoMap() {
    _mappings.clear();
    for (var field in _systemFields) {
      final key = field['key'] as String;
      int matchIdx = -1;

      for (int i = 0; i < _headers.length; i++) {
        final header = _headers[i].toLowerCase();
        if (key == 'name' && (header.contains('name') || header.contains('customer'))) {
          matchIdx = i;
          break;
        } else if (key == 'mobile' && (header.contains('mobile') || header.contains('phone') || header.contains('contact'))) {
          matchIdx = i;
          break;
        } else if (key == 'consumer_number' && (header.contains('consumer') || header.contains('consumer number') || header.contains('consumer no'))) {
          matchIdx = i;
          break;
        } else if (key == 'address' && header.contains('address')) {
          matchIdx = i;
          break;
        } else if (key == 'village' && (header.contains('village') || header.contains('city'))) {
          matchIdx = i;
          break;
        } else if (key == 'system_size' && (header.contains('requirement') || header.contains('system requirement') || header.contains('system_size') || header.contains('size') || header.contains('kw') || header.contains('system siz'))) {
          matchIdx = i;
          break;
        } else if (key == 'loan_required' && (header.contains('loan requ') || header.contains('loan required') || header.contains('loan yes/no'))) {
          matchIdx = i;
          break;
        } else if (key == 'stage' && (header.contains('status') || header.contains('stage') || header.contains('current stage') || header.contains('application stage') || header.contains('application status'))) {
          matchIdx = i;
          break;
        } else if (key == 'application_date' && (header.contains('date') || header.contains('created') || header.contains('application date'))) {
          matchIdx = i;
          break;
        } else if (key == 'pm_surya_ghar_application_id' && (header.contains('pm surya ghar application id') || header.contains('application id') || header.contains('surya ghar id') || header.contains('pm id') || header.contains('pm_surya_ghar_application_id'))) {
          matchIdx = i;
          break;
        } else if (key == 'reference' && (header.contains('reference') || header.contains('referred'))) {
          matchIdx = i;
          break;
        } else if (key == 'remarks' && (header.contains('remarks') || header.contains('notes') || header.contains('remark'))) {
          matchIdx = i;
          break;
        }
      }
      _mappings[key] = matchIdx;
    }
  }

  // Generate Preview step
  Future<void> _generatePreview() async {
    // 1. Validation check for column mappings
    if (_mappings['name'] == -1 || _mappings['mobile'] == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please map both "Customer Name" and "Mobile" columns.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = ref.read(supabaseClientProvider);

      // 2. Batch fetch existing mobiles and consumer numbers for duplicate checks
      final existingRes = await supabase.from('customers').select('mobile, consumer_number');
      final existingList = List<Map<String, dynamic>>.from(existingRes);
      final existingMobiles = existingList.map((e) => e['mobile']?.toString().trim()).where((m) => m != null).toSet();
      final existingConsumerNums = existingList
          .map((e) => e['consumer_number']?.toString().trim())
          .where((c) => c != null && c!.isNotEmpty)
          .toSet();

      final List<PreviewRow> previewList = [];

      for (int i = 1; i < _rawData.length; i++) {
        final row = _rawData[i];
        if (row.isEmpty) continue;

        // Map CSV values to System Keys
        final Map<String, String> rowData = {};
        for (var field in _systemFields) {
          final key = field['key'] as String;
          final colIdx = _mappings[key] ?? -1;
          if (colIdx >= 0 && colIdx < row.length) {
            rowData[key] = row[colIdx]?.toString().trim() ?? '';
          } else {
            rowData[key] = '';
          }
        }

        final previewRow = PreviewRow(
          originalIndex: i,
          data: rowData,
        );

        _validateRow(previewRow, existingMobiles, existingConsumerNums);
        previewList.add(previewRow);
      }

      setState(() {
        _previewRows = previewList;
        _currentStep = 2; // Move to Preview & Edit step
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating preview: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Row validation logic
  void _validateRow(PreviewRow row, Set<String?> existingMobiles, Set<String?> existingConsumerNums) {
    row.error = null;
    row.isDuplicate = false;

    final name = row.data['name'] ?? '';
    final mobile = row.data['mobile'] ?? '';
    final consumerNum = row.data['consumer_number'] ?? '';
    final stage = row.data['stage'] ?? '';

    // 1. Validate required fields
    if (name.isEmpty || mobile.isEmpty) {
      row.error = 'Customer Name and Mobile are required.';
      return;
    }

    // 2. Validate duplicates
    if (existingMobiles.contains(mobile) || (consumerNum.isNotEmpty && existingConsumerNums.contains(consumerNum))) {
      row.isDuplicate = true;
      return;
    }

    // 3. Validate and normalize Application Stage
    if (stage.isNotEmpty) {
      final cleanStage = stage.toLowerCase().trim();
      final matchedStage = _validStages.firstWhere(
        (s) => s.toLowerCase() == cleanStage,
        orElse: () => '',
      );
      if (matchedStage.isNotEmpty) {
        row.data['stage'] = matchedStage; // Normalize capitalization
      } else {
        row.error = 'Invalid Application Stage: "$stage"';
      }
    } else {
      // Default fallback stage if left empty
      row.data['stage'] = 'PM Surya Ghar Application';
    }
  }

  // Format and parse date strings like 07-08-2026 to YYYY-MM-DD
  String _parseDate(String rawDate) {
    final dateStr = rawDate.trim();
    if (dateStr.isEmpty) return DateTime.now().toIso8601String().split('T').first;
    
    try {
      final parts = dateStr.split(RegExp(r'[/.-]'));
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          // YYYY-MM-DD
          return '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
        } else if (parts[2].length == 4) {
          // DD-MM-YYYY
          return '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
        }
      }
    } catch (_) {}
    return DateTime.now().toIso8601String().split('T').first;
  }

  // Row Edit Dialog
  void _editRow(PreviewRow row) {
    final Map<String, String> tempData = Map.from(row.data);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Row #${row.originalIndex}'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: tempData['name'],
                        decoration: const InputDecoration(labelText: 'Customer Name *'),
                        onChanged: (val) => tempData['name'] = val.trim(),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['mobile'],
                        decoration: const InputDecoration(labelText: 'Mobile Number *'),
                        onChanged: (val) => tempData['mobile'] = val.trim(),
                        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['consumer_number'],
                        decoration: const InputDecoration(labelText: 'Consumer Number'),
                        onChanged: (val) => tempData['consumer_number'] = val.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['village'],
                        decoration: const InputDecoration(labelText: 'Village'),
                        onChanged: (val) => tempData['village'] = val.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['address'],
                        decoration: const InputDecoration(labelText: 'Address'),
                        onChanged: (val) => tempData['address'] = val.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['system_size'],
                        decoration: const InputDecoration(labelText: 'Requirement / System Size'),
                        onChanged: (val) => tempData['system_size'] = val.trim(),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: tempData['loan_required']!.isEmpty ? '' : (tempData['loan_required']!.toLowerCase().startsWith('y') ? 'Yes' : 'No'),
                        decoration: const InputDecoration(labelText: 'Loan Required'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('Not Specified (Auto)', style: TextStyle(color: Colors.grey))),
                          DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                          DropdownMenuItem(value: 'No', child: Text('No')),
                        ],
                        onChanged: (val) {
                          setDialogState(() => tempData['loan_required'] = val ?? '');
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _validStages.contains(tempData['stage']) ? tempData['stage'] : null,
                        decoration: const InputDecoration(labelText: 'Application Stage'),
                        items: _validStages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => tempData['stage'] = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['application_date'],
                        decoration: const InputDecoration(labelText: 'Application Date (e.g. DD-MM-YYYY)'),
                        onChanged: (val) => tempData['application_date'] = val.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['pm_surya_ghar_application_id'],
                        decoration: const InputDecoration(labelText: 'PM Surya Ghar Application ID'),
                        onChanged: (val) => tempData['pm_surya_ghar_application_id'] = val.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['reference'],
                        decoration: const InputDecoration(labelText: 'Reference'),
                        onChanged: (val) => tempData['reference'] = val.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tempData['remarks'],
                        decoration: const InputDecoration(labelText: 'Remarks'),
                        onChanged: (val) => tempData['remarks'] = val.trim(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      setState(() {
                        row.data = tempData;
                        // Re-validate row locally
                        _validateRow(row, {}, {});
                      });
                      Navigator.pop(context);
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

  // Execute database inserts
  Future<void> _processImport() async {
    final readyRows = _previewRows.where((r) => r.error == null && !r.isDuplicate).toList();
    if (readyRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid rows ready to import.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = ref.read(supabaseClientProvider);

      // Get current customer count for generated C00000X IDs
      final countResp = await supabase.from('customers').select('id');
      int currentCount = (countResp as List).length;

      int importedCount = 0;
      int errorCount = 0;

      for (var row in readyRows) {
        final generatedId = 'C${(currentCount + 1).toString().padLeft(6, '0')}';
        final stage = row.data['stage'] ?? 'PM Surya Ghar Application';
        final appDate = _parseDate(row.data['application_date'] ?? '');

        // 1. Explicitly check if "Loan Required" field is mapped and specified
        bool? loanRequired;
        if (_mappings['loan_required'] != -1) {
          final loanVal = row.data['loan_required']?.toLowerCase().trim() ?? '';
          if (loanVal.startsWith('y') || loanVal == 'true' || loanVal == '1') {
            loanRequired = true;
          } else if (loanVal.startsWith('n') || loanVal == 'false' || loanVal == '0') {
            loanRequired = false;
          }
        }
        
        // 2. Fall back to automatic stage-based loan selection if not explicitly provided
        if (loanRequired == null) {
          if (stage == 'Loan Processing') {
            loanRequired = true;
          } else if (['Installation', 'RTS', 'Subsidy', 'Completed'].contains(stage)) {
            loanRequired = false;
          } else {
            loanRequired = null;
          }
        }

        final insertData = {
          'customer_id': generatedId,
          'name': row.data['name'],
          'mobile': row.data['mobile'],
          'consumer_number': row.data['consumer_number']!.isEmpty ? null : row.data['consumer_number'],
          'village': row.data['village']!.isEmpty ? null : row.data['village'],
          'address': row.data['address']!.isEmpty ? null : row.data['address'],
          'system_size': row.data['system_size']!.isEmpty ? null : row.data['system_size'],
          'stage': stage,
          'pm_surya_ghar_application_id': row.data['pm_surya_ghar_application_id']!.isEmpty ? null : row.data['pm_surya_ghar_application_id'],
          'reference': row.data['reference']!.isEmpty ? null : row.data['reference'],
          'remarks': row.data['remarks']!.isEmpty ? null : row.data['remarks'],
          'loan_required': loanRequired,
          'application_date': appDate,
          'created_by': ref.read(currentUserProvider)?.id,
        };

        try {
          await supabase.from('customers').insert(insertData);
          currentCount++;
          importedCount++;
        } catch (_) {
          errorCount++;
        }
      }

      // Refresh customer list
      ref.invalidate(customerListProvider);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Import Status'),
            content: Text(
              'Successfully Imported: $importedCount\n'
              'Skipped/Errors: ${readyRows.length - importedCount + errorCount}',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to More screen
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Customers'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildCurrentStepView(),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 1:
        return _buildMappingStepView();
      case 2:
        return _buildPreviewStepView();
      case 0:
      default:
        return _buildFileSelectionStepView();
    }
  }

  // STEP 1: File Selection UI
  Widget _buildFileSelectionStepView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Icon(Icons.upload_file_outlined, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text(
                    'Upload CSV or Excel Spreadsheet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Supported file extensions: .csv, .xlsx\nMinimum required columns: Name, Mobile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _pickFile,
                    child: const Text('SELECT SPREADSHEET'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 2: Column Mapping UI
  Widget _buildMappingStepView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Column Mapping for $_fileName',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text('Match your file headers to Solar CRM system fields.'),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _systemFields.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, idx) {
                final field = _systemFields[idx];
                final key = field['key'] as String;
                final isRequired = field['required'] as bool;
                final currentMappedIdx = _mappings[key] ?? -1;

                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                field['label'] + (isRequired ? ' *' : ''),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (isRequired)
                                const Text(
                                  'Required mapping',
                                  style: TextStyle(fontSize: 10, color: Colors.red),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: currentMappedIdx == -1 ? null : currentMappedIdx,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 10),
                              border: OutlineInputBorder(),
                            ),
                            hint: const Text('Skip Column'),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('Skip Column', style: TextStyle(color: Colors.grey)),
                              ),
                              ...List.generate(_headers.length, (i) {
                                return DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(_headers[i]),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _mappings[key] = val ?? -1;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 0),
                  child: const Text('BACK'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _generatePreview,
                  child: const Text('PREVIEW'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // STEP 3: Preview UI
  Widget _buildPreviewStepView() {
    final total = _previewRows.length;
    final duplicates = _previewRows.where((r) => r.isDuplicate).length;
    final errors = _previewRows.where((r) => r.error != null).length;
    final ready = total - duplicates - errors;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Import Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Total Rows: $total', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          // Summary bar
          Row(
            children: [
              Expanded(child: _buildSummaryBadge('READY', ready, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildSummaryBadge('DUPLICATES', duplicates, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _buildSummaryBadge('ERRORS', errors, Colors.red)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _previewRows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final row = _previewRows[idx];

                Color cardColor = Colors.green.shade50;
                String statusLabel = 'Ready to Import';
                IconData statusIcon = Icons.check_circle_outline;
                Color statusColor = Colors.green;

                if (row.isDuplicate) {
                  cardColor = Colors.orange.shade50;
                  statusLabel = 'Already Exists (Skip)';
                  statusIcon = Icons.warning_amber_outlined;
                  statusColor = Colors.orange;
                } else if (row.error != null) {
                  cardColor = Colors.red.shade50;
                  statusLabel = row.error!;
                  statusIcon = Icons.error_outline;
                  statusColor = Colors.red;
                }

                return Card(
                  color: cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row.data['name'] ?? "Unknown"} • ${row.data['mobile'] ?? "No Mobile"}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text('Stage: ${row.data['stage'] ?? "N/A"}'),
                              if (row.data['consumer_number']!.isNotEmpty)
                                Text('Consumer No: ${row.data['consumer_number']}'),
                              if (row.data['village']!.isNotEmpty)
                                Text('Village: ${row.data['village']}'),
                              if (row.data['loan_required']!.isNotEmpty)
                                Text('Loan Required: ${row.data['loan_required']}'),
                              if (row.data['application_date']!.isNotEmpty)
                                Text('App Date: ${row.data['application_date']}'),
                              if (row.data['remarks']!.isNotEmpty)
                                Text('Remarks: ${row.data['remarks']}'),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(statusIcon, size: 16, color: statusColor),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                          onPressed: () => _editRow(row),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: const Text('BACK'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: ready > 0 ? _processImport : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text('START IMPORT'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 2),
          Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}
