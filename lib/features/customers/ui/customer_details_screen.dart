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
import '../../../core/services/permission_service.dart';
import '../../../core/utils/priority_calculator.dart';


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
  String? _expandedSection;

  int _getStageIndex(String? stage) {
    if (stage == null) return 0;
    final s = stage.trim().toLowerCase();
    if (s == 'lead') return 0;
    if (s.contains('application')) return 1;
    if (s.contains('loan')) return 2;
    if (s.contains('material required') || s == 'material_required') return 3;
    if (s.contains('material dispatched') || s == 'material_dispatched') return 4;
    if (s.contains('installation')) return 5;
    if (s.contains('rts')) return 6;
    if (s.contains('subsidy')) return 7;
    if (s.contains('completed')) return 8;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _customerData = Map<String, dynamic>.from(widget.customer);
    _currentStage = _customerData['stage'] ?? 'Lead';
    _loanRequired = _customerData['loan_required'] ?? ((_customerData['payment_type'] ?? 'CASH') == 'LOAN');
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

  Future<void> _showUpdateLoanDialog() async {
    final formKey = GlobalKey<FormState>();
    final bankCtrl = TextEditingController(text: _customerData['bank_name']);
    final amountCtrl = TextEditingController(text: _customerData['loan_amount']?.toString() ?? '');
    final refCtrl = TextEditingController(text: _customerData['loan_reference_number']);
    final problemRemarksCtrl = TextEditingController(text: _customerData['loan_problem_remarks']);
    
    String tempStage = _customerData['loan_stage'] ?? 'NOT STARTED';
    String tempIssueStatus = _customerData['loan_issue_status'] ?? 'NO ISSUE';
    String? tempProblemType = _customerData['loan_problem_type'];
    DateTime? tempAppDate = _customerData['loan_application_date'] != null
        ? DateTime.tryParse(_customerData['loan_application_date'])
        : null;

    final stages = [
      'NOT STARTED',
      'OFFICE FILE READY',
      'PRINTED',
      'SENT TO BANK',
      '1ST STAGE',
      '2ND STAGE',
      'APPROVED',
      'REJECTED'
    ];

    final issueStatuses = ['NO ISSUE', 'OPEN PROBLEM', 'RESOLVED'];

    final problemTypes = [
      'Document Missing',
      'Customer Signature Pending',
      'Bank Query',
      'Eligibility Issue',
      'Income Document Problem',
      'Name / Document Mismatch',
      'Technical Problem',
      'Other'
    ];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Update Loan Details', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: bankCtrl,
                        decoration: const InputDecoration(labelText: 'Bank Name', prefixIcon: Icon(Icons.account_balance)),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: amountCtrl,
                        decoration: const InputDecoration(labelText: 'Loan Amount (₹)', prefixIcon: Icon(Icons.currency_rupee)),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: tempStage,
                        decoration: const InputDecoration(labelText: 'Current Loan Stage', prefixIcon: Icon(Icons.playlist_add_check)),
                        items: stages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => tempStage = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: tempIssueStatus,
                        decoration: const InputDecoration(labelText: 'Issue Status', prefixIcon: Icon(Icons.warning_amber_outlined)),
                        items: issueStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              tempIssueStatus = val;
                              if (val != 'OPEN PROBLEM') {
                                tempProblemType = null;
                              }
                            });
                          }
                        },
                      ),
                      if (tempIssueStatus == 'OPEN PROBLEM') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: tempProblemType,
                          decoration: const InputDecoration(labelText: 'Problem Type *', prefixIcon: Icon(Icons.help_outline)),
                          hint: const Text('Select Problem Type'),
                          validator: (val) => val == null ? 'Required' : null,
                          items: problemTypes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (val) {
                            setDialogState(() => tempProblemType = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: problemRemarksCtrl,
                          decoration: const InputDecoration(labelText: 'Problem Details / Remarks', prefixIcon: Icon(Icons.notes)),
                          maxLines: 2,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refCtrl,
                        decoration: const InputDecoration(labelText: 'Loan Ref / Application No.', prefixIcon: Icon(Icons.confirmation_number_outlined)),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: tempAppDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setDialogState(() => tempAppDate = date);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Application Date', prefixIcon: Icon(Icons.calendar_today)),
                          child: Text(tempAppDate != null ? AppDateUtils.formatDate(tempAppDate!.toIso8601String()) : 'Select Date'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.pop(ctx);
                    await _saveLoanDetails(
                      bankName: bankCtrl.text.trim(),
                      loanAmount: double.tryParse(amountCtrl.text.trim()),
                      loanStage: tempStage,
                      loanIssueStatus: tempIssueStatus,
                      loanProblemType: tempIssueStatus == 'OPEN PROBLEM' ? tempProblemType : null,
                      loanProblemRemarks: tempIssueStatus == 'OPEN PROBLEM' ? problemRemarksCtrl.text.trim() : null,
                      loanReferenceNumber: refCtrl.text.trim(),
                      loanApplicationDate: tempAppDate?.toIso8601String().split('T').first,
                    );
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

  Future<void> _showResolveLoanProblemDialog() async {
    final remarksCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Loan Problem', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Are you sure you want to mark this issue as resolved?'),
            const SizedBox(height: 12),
            TextFormField(
              controller: remarksCtrl,
              decoration: const InputDecoration(labelText: 'Resolution Remarks (Optional)', prefixIcon: Icon(Icons.check_circle_outline)),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveLoanDetails(
                bankName: _customerData['bank_name'] ?? '',
                loanAmount: _customerData['loan_amount'] != null ? double.tryParse(_customerData['loan_amount'].toString()) : null,
                loanStage: _customerData['loan_stage'] ?? 'NOT STARTED',
                loanIssueStatus: 'RESOLVED',
                loanProblemType: null,
                loanProblemRemarks: null,
                loanReferenceNumber: _customerData['loan_reference_number'] ?? '',
                loanApplicationDate: _customerData['loan_application_date'],
                loanResolutionRemarks: remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
              );
            },
            child: const Text('RESOLVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLoanDetails({
    required String bankName,
    required double? loanAmount,
    required String loanStage,
    required String loanIssueStatus,
    required String? loanProblemType,
    required String? loanProblemRemarks,
    required String loanReferenceNumber,
    required String? loanApplicationDate,
    String? loanResolutionRemarks,
  }) async {
    setState(() => _isAdvancing = true);

    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final customerId = _customerData['id'];

    // Build local state map (used regardless of DB success)
    final localData = <String, dynamic>{
      'bank_name': bankName.isEmpty ? null : bankName,
      'loan_amount': loanAmount,
      'loan_stage': loanStage,
      'loan_issue_status': loanIssueStatus,
      'loan_problem_type': loanProblemType,
      'loan_problem_remarks': loanProblemRemarks,
      'loan_reference_number': loanReferenceNumber.isEmpty ? null : loanReferenceNumber,
      'loan_application_date': loanApplicationDate,
      'loan_resolution_remarks': loanResolutionRemarks,
      'loan_updated_at': DateTime.now().toIso8601String(),
    };

    bool savedToDb = false;

    // ATTEMPT 1: Full update with all loan columns
    try {
      await supabase.from('customers').update(localData).eq('id', customerId);
      savedToDb = true;
    } catch (_) {}

    // ATTEMPT 2: Minimal update (only loan_stage — most critical)
    if (!savedToDb) {
      try {
        await supabase
            .from('customers')
            .update({'loan_stage': loanStage})
            .eq('id', customerId);
        savedToDb = true;
      } catch (_) {}
    }

    // ATTEMPT 3: Column-by-column best effort
    if (!savedToDb) {
      for (final entry in localData.entries) {
        try {
          await supabase
              .from('customers')
              .update({entry.key: entry.value})
              .eq('id', customerId);
        } catch (_) {}
      }
    }

    // Always update last_meaningful_update separately
    try {
      await supabase
          .from('customers')
          .update({'last_meaningful_update': DateTime.now().toUtc().toIso8601String()})
          .eq('id', customerId);
    } catch (_) {}

    // Log activity
    try {
      if (user != null) {
        final staffNameRes = await supabase
            .from('staff')
            .select('name')
            .eq('id', user.id)
            .maybeSingle();
        final staffName = staffNameRes?['name'] ?? 'Staff';
        final oldStage = _customerData['loan_stage'] ?? 'NOT STARTED';

        if (oldStage != loanStage) {
          await ActivityLogger.log(
            supabase: supabase,
            customerId: customerId,
            action: 'loan_stage_changed',
            description: 'Loan Stage changed: $oldStage → $loanStage by $staffName',
            performedBy: user.id,
          );
        } else {
          await ActivityLogger.log(
            supabase: supabase,
            customerId: customerId,
            action: 'loan_updated',
            description: 'Loan details updated by $staffName',
            performedBy: user.id,
          );
        }
      }
    } catch (_) {}

    // Always update local UI state
    if (mounted) {
      setState(() {
        _customerData.addAll(localData);
        _isAdvancing = false;
      });
      ref.invalidate(customerListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(savedToDb
              ? 'Loan details saved successfully!'
              : 'Saved locally. Please run the SQL migration in Supabase to persist all fields.'),
          backgroundColor: savedToDb ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }


  Future<void> _showChangePriorityDialog(String current, String? manual) async {
    final formKey = GlobalKey<FormState>();
    String tempManual = manual ?? 'NORMAL';
    final noteCtrl = TextEditingController(text: _customerData['followup_note']);
    DateTime? tempFollowupDate = _customerData['next_followup_date'] != null
        ? DateTime.tryParse(_customerData['next_followup_date'])
        : null;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Priority & Follow-up', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: tempManual,
                        decoration: const InputDecoration(labelText: 'Manual Priority', prefixIcon: const Icon(Icons.priority_high)),
                        items: const [
                          DropdownMenuItem(value: 'NORMAL', child: Text('🟢 NORMAL')),
                          DropdownMenuItem(value: 'MEDIUM', child: Text('🟠 MEDIUM')),
                          DropdownMenuItem(value: 'HIGH', child: Text('🔴 HIGH')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => tempManual = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(labelText: 'Follow-up Note', prefixIcon: const Icon(Icons.note_alt_outlined)),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: tempFollowupDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                          );
                          if (date != null) {
                            setDialogState(() => tempFollowupDate = date);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Next Follow-up Date', prefixIcon: const Icon(Icons.calendar_month)),
                          child: Text(
                            tempFollowupDate != null ? AppDateUtils.formatDate(tempFollowupDate!.toIso8601String()) : 'Select Date',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    
                    showDialog(
                      context: this.context,
                      barrierDismissible: false,
                      builder: (c) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      final supabase = ref.read(supabaseClientProvider);
                      final user = ref.read(currentUserProvider);

                      final isLead = _currentStage == 'Lead';
                      final table = isLead ? 'leads' : 'customers';

                      final updateData = {
                        'manual_priority': tempManual,
                        'followup_note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                        'next_followup_date': tempFollowupDate?.toIso8601String().split('T').first,
                        'last_meaningful_update': DateTime.now().toUtc().toIso8601String(),
                      };

                      await supabase.from(table).update(updateData).eq('id', _customerData['id']);

                      if (user != null) {
                        try {
                          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
                          final staffName = staffNameRes?['name'] ?? 'Staff member';
                          
                          String changeDesc = '$staffName updated priority/follow-up details.';
                          if (manual != tempManual) {
                            changeDesc = '$staffName manually changed priority: $tempManual';
                          }

                          await ActivityLogger.log(
                            supabase: supabase,
                            customerId: _customerData['id'],
                            action: 'priority_changed',
                            description: changeDesc,
                            performedBy: user.id,
                          );
                        } catch (_) {}
                      }

                      // Fetch updated
                      final updated = await supabase
                          .from(table)
                          .select(isLead ? '*' : '*, site_installation_tasks(task_type, status)')
                          .eq('id', _customerData['id'])
                          .single();

                      if (mounted) {
                        Navigator.pop(this.context); // Close loading
                        setState(() {
                          _customerData = updated;
                        });
                        ref.invalidate(customerListProvider);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Priority updated successfully!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        Navigator.pop(this.context); // Close loading
                        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  Future<void> _uploadCustomerPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes == null) {
          throw 'No file data found';
        }
        
        setState(() => _isAdvancing = true);
        final supabase = ref.read(supabaseClientProvider);
        final customerId = _customerData['id'];
        
        final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final path = 'customer_pdfs/$customerId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        
        await supabase.storage.from('task_attachments').uploadBinary(
          path,
          file.bytes!,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
        
        final publicUrl = supabase.storage.from('task_attachments').getPublicUrl(path);
        
        await supabase.from('customers').update({
          'pdf_url': publicUrl,
          'pdf_name': file.name,
        }).eq('id', customerId);
        
        // Update local state
        setState(() {
          _customerData['pdf_url'] = publicUrl;
          _customerData['pdf_name'] = file.name;
        });

        // Log activity
        final user = ref.read(currentUserProvider);
        if (user != null) {
          try {
            final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
            final staffName = staffNameRes?['name'] ?? 'Staff member';
            await ActivityLogger.log(
              supabase: supabase,
              customerId: customerId,
              action: 'pdf_uploaded',
              description: '$staffName uploaded PDF: ${file.name}',
              performedBy: user.id,
            );
          } catch (_) {}
        }

        ref.invalidate(customerHistoryProvider(customerId));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF uploaded successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

  Future<void> _advanceStage() async {
    String? nextStage;
    String targetPaymentType = _customerData['payment_type'] ?? 'CASH';

    if (_currentStage == 'Lead') {
      String selectedConvPaymentType = 'CASH';
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Convert Lead to Customer', style: TextStyle(fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Are you sure you want to convert this Lead to a Customer?'),
                    const SizedBox(height: 16),
                    const Text('SELECT PAYMENT TYPE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('CASH', style: TextStyle(fontWeight: FontWeight.bold))),
                            selected: selectedConvPaymentType == 'CASH',
                            selectedColor: Colors.green.shade100,
                            onSelected: (val) {
                              if (val) setDialogState(() => selectedConvPaymentType = 'CASH');
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('LOAN', style: TextStyle(fontWeight: FontWeight.bold))),
                            selected: selectedConvPaymentType == 'LOAN',
                            selectedColor: Colors.blue.shade100,
                            onSelected: (val) {
                              if (val) setDialogState(() => selectedConvPaymentType = 'LOAN');
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('CONVERT'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (confirm != true) return;
      nextStage = 'PM Surya Ghar Application';
      targetPaymentType = selectedConvPaymentType;

    } else if (_currentStage == 'PM Surya Ghar Application') {
      String selectedType = (_customerData['payment_type'] == 'LOAN' || _loanRequired == true) ? 'LOAN' : 'CASH';
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Advance to Next Stage', style: TextStyle(fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Customer Payment Type:'),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => setDialogState(() => selectedType = 'LOAN'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedType == 'LOAN' ? Colors.blue.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedType == 'LOAN' ? Colors.blue : Colors.grey.shade300,
                            width: selectedType == 'LOAN' ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance, color: selectedType == 'LOAN' ? Colors.blue : Colors.grey),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LOAN CUSTOMER',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: selectedType == 'LOAN' ? Colors.blue.shade900 : Colors.black87,
                                    ),
                                  ),
                                  const Text('Next: 🏦 Loan Processing', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                            if (selectedType == 'LOAN') const Icon(Icons.check_circle, color: Colors.blue),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => setDialogState(() => selectedType = 'CASH'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedType == 'CASH' ? Colors.green.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedType == 'CASH' ? Colors.green : Colors.grey.shade300,
                            width: selectedType == 'CASH' ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.payments_outlined, color: selectedType == 'CASH' ? Colors.green : Colors.grey),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CASH CUSTOMER',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: selectedType == 'CASH' ? Colors.green.shade900 : Colors.black87,
                                    ),
                                  ),
                                  const Text('Next: 📦 Material Required', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                            if (selectedType == 'CASH') const Icon(Icons.check_circle, color: Colors.green),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('ADVANCE'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (confirm != true) return;
      targetPaymentType = selectedType;
      nextStage = selectedType == 'LOAN' ? 'Loan Processing' : 'Material Required';

    } else {
      final isLoan = (_customerData['payment_type'] == 'LOAN') || _loanRequired == true || _currentStage == 'Loan Processing';
      nextStage = StageConfig.nextStage(_currentStage, loanRequired: isLoan);
      if (nextStage == null) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Advance Stage?'),
          content: Text('Are you sure you want to advance from $_currentStage to $nextStage?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('ADVANCE')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isAdvancing = true);

    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);

      // --- LEAD TO CUSTOMER CONVERSION (special path) ---
      if (_currentStage == 'Lead') {
        final leadId = _customerData['id'] as String;

        // 1. Check if customer row already exists (idempotent)
        final existingCustomer = await supabase
            .from('customers')
            .select('id')
            .eq('id', leadId)
            .maybeSingle();

        if (existingCustomer == null) {
          // 2. Count existing customers to generate customer_id
          final countRes = await supabase.from('customers').select('id');
          final newNum = (countRes as List).length + 1;
          final generatedCustomerId = 'C${newNum.toString().padLeft(6, '0')}';

          // 3. Insert the customer row FIRST (only base columns that always exist)
          await supabase.from('customers').insert({
            'id': leadId,
            'customer_id': generatedCustomerId,
            'name': _customerData['name'] ?? 'N/A',
            'mobile': _customerData['mobile'] ?? 'N/A',
            'village': _customerData['village'],
            'address': _customerData['address'],
            'remarks': _customerData['remarks'],
            'stage': nextStage,
            'created_by': _customerData['created_by'],
            'created_at': _customerData['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });

          // 4. Try to update optional columns
          try {
            await supabase.from('customers').update({
              'payment_type': targetPaymentType,
              'loan_required': targetPaymentType == 'LOAN',
              'last_meaningful_update': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', leadId);
          } catch (_) {}
        }

        // 4. Update lead status to converted
        await supabase.from('leads')
            .update({'status': 'converted'})
            .eq('id', leadId);

        // 5. Insert stage history
        await supabase.from('stage_history').insert({
          'customer_id': leadId,
          'old_stage': _currentStage,
          'new_stage': nextStage,
          'changed_by': user?.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });

        setState(() => _currentStage = nextStage!);

      } else {
        // --- NORMAL STAGE ADVANCE (existing customer) ---
        await supabase.from('customers').update({
          'stage': nextStage,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _customerData['id']);

        try {
          await supabase.from('stage_history').insert({
            'customer_id': _customerData['id'],
            'old_stage': _currentStage,
            'new_stage': nextStage,
            'changed_by': user?.id,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}

        try {
          await supabase.from('customers').update({
            'payment_type': targetPaymentType,
            'loan_required': targetPaymentType == 'LOAN',
            'last_meaningful_update': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', _customerData['id']);
        } catch (_) {}

        setState(() => _currentStage = nextStage!);
      }

      // Fetch updated customer details
      final updated = await supabase
          .from('customers')
          .select('*, site_installation_tasks(task_type, status)')
          .eq('id', _customerData['id'])
          .single();

      setState(() {
        _customerData = updated;
        _loanRequired = _customerData['loan_required'];
      });
      
      // Refresh providers
      ref.invalidate(customerHistoryProvider(_customerData['id']));
      ref.invalidate(customerListProvider);
      
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
    String tempPaymentType = _customerData['payment_type'] ?? 'CASH';
    String tempStage = _currentStage;
    final availableStages = StageConfig.stages.where((s) => s != 'Lead').toList();

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
                      DropdownButtonFormField<String>(
                        value: tempPaymentType,
                        decoration: const InputDecoration(labelText: 'Payment Type'),
                        items: const [
                          DropdownMenuItem(value: 'CASH', child: Text('CASH')),
                          DropdownMenuItem(value: 'LOAN', child: Text('LOAN')),
                        ],
                        onChanged: (val) => setDialogState(() => tempPaymentType = val ?? 'CASH'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: availableStages.contains(tempStage) ? tempStage : null,
                        decoration: const InputDecoration(labelText: 'Stage'),
                        items: availableStages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) => setDialogState(() => tempStage = val ?? tempStage),
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
                          'stage': tempStage,
                          'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
                          'pm_surya_ghar_application_id': pmAppIdCtrl.text.trim().isEmpty ? null : pmAppIdCtrl.text.trim(),
                          'reference': referenceCtrl.text.trim().isEmpty ? null : referenceCtrl.text.trim(),
                          'updated_at': DateTime.now().toUtc().toIso8601String(),
                        };

                        await supabase.from('customers').update(updateData).eq('id', _customerData['id']);

                        try {
                          await supabase.from('customers').update({
                            'payment_type': tempPaymentType,
                            'loan_required': tempPaymentType == 'LOAN',
                            'last_meaningful_update': DateTime.now().toUtc().toIso8601String(),
                          }).eq('id', _customerData['id']);
                        } catch (_) {}

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
                            _currentStage = updated['stage'] ?? tempStage;
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

    final tasksList = tasksAsync.value ?? [];
    final createdAt = customer['created_at'] != null ? DateTime.tryParse(customer['created_at']) : null;
    final lastUpdate = customer['last_meaningful_update'] != null ? DateTime.tryParse(customer['last_meaningful_update']) : null;
    final loanIssueStatus = customer['loan_issue_status'] as String?;
    final combinedTasks = [
      ...tasksList,
      ...(customer['site_installation_tasks'] as List? ?? []),
    ];

    final automaticPriority = PriorityCalculator.calculateAutomatic(
      createdAt: createdAt,
      lastMeaningfulUpdate: lastUpdate,
      loanIssueStatus: loanIssueStatus,
      tasks: combinedTasks,
    );
    final manualPriority = customer['manual_priority'] as String?;
    final finalPriority = PriorityCalculator.calculateFinal(automatic: automaticPriority, manual: manualPriority);
    final customerAge = PriorityCalculator.getCustomerAge(createdAt);
    final lastUpdateLabel = PriorityCalculator.getLastUpdateLabel(lastUpdate, createdAt);

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
              
              if (stage == 'Loan Processing') {
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
          final permsAsync = ref.watch(currentUserPermissionsProvider);
          return permsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error permissions: $e')),
            data: (perms) {
              final canViewLoan = perms.canViewField('loan_amount');
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                // --- Customer Info Card (Basic Info Only by Default) ---
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          customer['name'] ?? 'N/A',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Builder(builder: (_) {
                                    final isLoanCustomer = (customer['payment_type'] == 'LOAN') ||
                                        _currentStage == 'Loan Processing' ||
                                        customer['loan_required'] == true;
                                    final displayPaymentType = isLoanCustomer ? 'LOAN' : 'CASH';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isLoanCustomer
                                            ? Colors.blue.shade50
                                            : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isLoanCustomer
                                              ? Colors.blue.shade300
                                              : Colors.green.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        displayPaymentType,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isLoanCustomer
                                              ? Colors.blue.shade800
                                              : Colors.green.shade800,
                                        ),
                                      ),
                                    );
                                  }),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    customer['mobile'] ?? 'N/A',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.blueGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (customer['village'] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Village: ${customer['village']}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Priority: ${PriorityCalculator.getPriorityEmoji(finalPriority)} $finalPriority',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: finalPriority == 'HIGH'
                                              ? Colors.red
                                              : (finalPriority == 'MEDIUM' ? Colors.orange : Colors.green),
                                        ),
                                      ),
                                      Text(
                                        'Age: $customerAge Days',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54),
                                      ),
                                      Text(
                                        'Last Update: $lastUpdateLabel',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (customer['priority'] == true)
                              const Icon(Icons.star, color: Colors.amber, size: 28),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.call),
                                label: const Text('CALL'),
                                onPressed: _callCustomer,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.message, color: Colors.green),
                                label: const Text('WHATSAPP'),
                                onPressed: _whatsappCustomer,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Chip(
                              label: Text(
                                _currentStage,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              backgroundColor: StageConfig.stageColor(_currentStage),
                            ),
                            if (!StageConfig.isCompleted(_currentStage) && (role == 'admin' || role == 'office_staff'))
                              ElevatedButton.icon(
                                onPressed: _isAdvancing ? null : _advanceStage,
                                icon: _isAdvancing
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Icon(_currentStage == 'Lead' ? Icons.check_circle_outline : Icons.arrow_forward, size: 16),
                                label: Text(
                                  _currentStage == 'Lead' ? 'CONVERT TO CUSTOMER' : 'NEXT STAGE',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Collapsible 0: Priority & Follow-up
                _buildCollapsibleSection(
                  title: 'Priority & Follow-up',
                  sectionKey: 'priority_followup',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Current Priority:', finalPriority),
                      _buildDetailRow('Automatic Priority:', automaticPriority),
                      _buildDetailRow('Manual Priority:', manualPriority ?? 'Not Set'),
                      _buildDetailRow('Last Meaningful Update:', lastUpdateLabel),
                      _buildDetailRow('Customer Age:', '$customerAge Days'),
                      if (customer['next_followup_date'] != null)
                        _buildDetailRow('Next Follow-up Date:', AppDateUtils.formatDate(customer['next_followup_date'].toString())),
                      if (customer['followup_note'] != null && customer['followup_note'].toString().isNotEmpty)
                        _buildDetailRow('Follow-up Note:', customer['followup_note'].toString()),
                      if (role == 'admin' || role == 'office_staff') ...[
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('CHANGE PRIORITY'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _showChangePriorityDialog(finalPriority, manualPriority),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_getStageIndex(_currentStage) >= 1) ...[
                  // Collapsible 1: Electricity & PM Surya Ghar
                  _buildCollapsibleSection(
                    title: 'Electricity & PM Surya Ghar',
                    sectionKey: 'electricity',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow('Consumer No:', customer['consumer_number'] ?? 'N/A'),
                        _buildDetailRow('PM Surya Ghar ID:', customer['pm_surya_ghar_application_id'] ?? 'N/A'),
                        _buildDetailRow('System Size:', customer['system_size'] ?? 'N/A'),
                        _buildDetailRow(
                          'Application Date:',
                          customer['application_date'] != null
                              ? '${AppDateUtils.formatDate(customer['application_date'])} (${AppDateUtils.applicationAgeLabel(customer['application_date'])})'
                              : 'N/A',
                        ),
                        if (customer['reference'] != null && customer['reference'].toString().isNotEmpty)
                          _buildDetailRow('Reference:', customer['reference'].toString()),
                        if (customer['remarks'] != null && customer['remarks'].toString().isNotEmpty)
                          _buildDetailRow('Remarks:', customer['remarks'].toString()),
                        creatorAsync.when(
                          data: (name) => name != null
                              ? _buildDetailRow('Created By:', name)
                              : const SizedBox.shrink(),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),

                        // Stage specific Details
                        if (_currentStage == 'PM Surya Ghar Application') ...[
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text('Loan Required?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                          const SizedBox(height: 8),
                          _buildDetailRow('Loan Required:', _loanRequired == true ? "Yes" : "No"),
                        ],

                        if (_getStageIndex(_currentStage) >= 6) ...[
                          const SizedBox(height: 16),
                          _buildRtsDetailsSection(),
                        ],

                        if (_getStageIndex(_currentStage) >= 7) ...[
                          const SizedBox(height: 16),
                          _buildSubsidyDetailsSection(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (((customer['payment_type'] == 'LOAN') || _currentStage == 'Loan Processing' || customer['loan_required'] == true) && _getStageIndex(_currentStage) >= 1 && canViewLoan) ...[
                  // Collapsible: Loan
                  _buildCollapsibleSection(
                    title: 'Loan',
                    sectionKey: 'loan',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_customerData['bank_name'] == null && (_customerData['loan_stage'] == null || _customerData['loan_stage'] == 'NOT STARTED')) ...[
                          const Text(
                            'NO LOAN DETAILS',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          if (role == 'admin' || role == 'office_staff')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('ADD LOAN'),
                                onPressed: _showUpdateLoanDialog,
                              ),
                            ),
                        ] else ...[
                          _buildDetailRow('Bank:', _customerData['bank_name'] ?? 'N/A'),
                          _buildDetailRow(
                            'Loan Amount:',
                            _customerData['loan_amount'] != null ? '₹${_customerData['loan_amount']}' : 'N/A',
                          ),
                          _buildDetailRow('Current Stage:', _customerData['loan_stage'] ?? 'NOT STARTED'),
                          
                          Row(
                            children: [
                              const SizedBox(
                                width: 140,
                                child: Text(
                                  'Issue Status:',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _customerData['loan_issue_status'] == 'OPEN PROBLEM'
                                      ? Colors.red.shade50
                                      : (_customerData['loan_issue_status'] == 'RESOLVED' ? Colors.green.shade50 : Colors.blue.shade50),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _customerData['loan_issue_status'] == 'OPEN PROBLEM'
                                        ? Colors.red.shade200
                                        : (_customerData['loan_issue_status'] == 'RESOLVED' ? Colors.green.shade200 : Colors.blue.shade200),
                                  ),
                                ),
                                child: Text(
                                  _customerData['loan_issue_status'] ?? 'NO ISSUE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _customerData['loan_issue_status'] == 'OPEN PROBLEM'
                                        ? Colors.red
                                        : (_customerData['loan_issue_status'] == 'RESOLVED' ? Colors.green : Colors.blue),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          if (_customerData['loan_issue_status'] == 'OPEN PROBLEM') ...[
                            const SizedBox(height: 8),
                            _buildDetailRow('Problem Type:', _customerData['loan_problem_type'] ?? 'N/A'),
                            if (_customerData['loan_problem_remarks'] != null)
                              _buildDetailRow('Details:', _customerData['loan_problem_remarks']!),
                            const SizedBox(height: 8),
                            if (role == 'admin' || role == 'office_staff')
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                  label: const Text('MARK AS RESOLVED', style: TextStyle(color: Colors.green)),
                                  onPressed: _showResolveLoanProblemDialog,
                                ),
                              ),
                          ],

                          if (_customerData['loan_issue_status'] == 'RESOLVED' && _customerData['loan_resolution_remarks'] != null) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow('Res. Remarks:', _customerData['loan_resolution_remarks']!),
                          ],

                          const SizedBox(height: 12),
                          
                          Card(
                            elevation: 0,
                            color: Colors.grey.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                title: const Text('MORE LOAN DETAILS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                                childrenPadding: const EdgeInsets.all(12),
                                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDetailRow(
                                    'Application Date:',
                                    _customerData['loan_application_date'] != null
                                        ? AppDateUtils.formatDate(_customerData['loan_application_date'])
                                        : 'N/A',
                                  ),
                                  _buildDetailRow('Reference No:', _customerData['loan_reference_number'] ?? 'N/A'),
                                  if (_customerData['loan_updated_at'] != null)
                                    _buildDetailRow(
                                      'Last Updated:',
                                      AppDateUtils.formatDateTime(_customerData['loan_updated_at']),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          if (role == 'admin' || role == 'office_staff') ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('UPDATE LOAN'),
                                onPressed: _showUpdateLoanDialog,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_getStageIndex(_currentStage) >= 3) ...[
                  // Collapsible 2: Site Material
                  _buildCollapsibleSection(
                    title: 'Site Material',
                    sectionKey: 'material',
                    child: _MaterialSummaryCard(
                      customerId: customer['id'],
                      customerName: customer['name'] ?? '',
                      pmSuryaGharApplicationId: customer['pm_surya_ghar_application_id'],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_getStageIndex(_currentStage) >= 5) ...[
                  // Collapsible: Installation Sub-stages (Structure, Wiring, Panel)
                  _buildCollapsibleSection(
                    title: 'Installation',
                    sectionKey: 'installation',
                    child: _InstallationSummaryCard(
                      customerId: customer['id'],
                      customerName: customer['name'] ?? '',
                      role: role ?? '',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Collapsible 3: Address
                _buildCollapsibleSection(
                  title: 'Address',
                  sectionKey: 'address',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Village:', customer['village'] ?? 'N/A'),
                      const SizedBox(height: 8),
                      const Text(
                        'Full Address:',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customer['address'] ?? 'N/A',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('OPEN MAP'),
                          onPressed: () async {
                            final address = customer['address'] ?? customer['village'] ?? '';
                            if (address.isEmpty) return;
                            final Uri url = Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not open map.')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_getStageIndex(_currentStage) >= 2) ...[
                  // Collapsible 4: Tasks
                  _buildCollapsibleSection(
                    title: 'Tasks',
                    sectionKey: 'tasks',
                    child: tasksAsync.when(
                      data: (tasks) {
                        if (tasks.isEmpty) {
                          return const Text('No tasks for this customer.', style: TextStyle(color: Colors.grey));
                        }
                        return Column(
                          children: tasks.map((task) {
                            final staffList = task['task_staff'] as List? ?? [];
                            final staffNames = staffList
                                .map((ts) => (ts['staff'] as Map?)?['name'] ?? '')
                                .where((name) => name.isNotEmpty)
                                .join(', ');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                title: Text(task['name'] ?? 'Task', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    _buildDetailRow('Status:', (task['status'] ?? 'N/A').toUpperCase()),
                                    _buildDetailRow('Assigned Staff:', staffNames.isNotEmpty ? staffNames : 'Unassigned'),
                                    if (task['due_date'] != null)
                                      _buildDetailRow('Due Date:', AppDateUtils.formatDate(task['due_date'])),
                                  ],
                                ),
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
                  ),
                  const SizedBox(height: 16),
                ],

                if (_getStageIndex(_currentStage) >= 3) ...[
                  // Collapsible 3: PDF Document
                  _buildCollapsibleSection(
                    title: 'PDF & Documents',
                    sectionKey: 'pdf',
                    child: Builder(
                      builder: (context) {
                        final pdfUrl = customer['pdf_url'] as String?;
                        final pdfName = customer['pdf_name'] as String? ?? 'document.pdf';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (pdfUrl != null && pdfUrl.isNotEmpty) ...[
                              Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf, color: Colors.red, size: 28),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      pdfName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.remove_red_eye_outlined),
                                      label: const Text('VIEW'),
                                      onPressed: () async {
                                        final Uri url = Uri.parse(pdfUrl);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url, mode: LaunchMode.externalApplication);
                                        } else {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Could not open PDF')),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.sync),
                                      label: const Text('REPLACE'),
                                      onPressed: _uploadCustomerPdf,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const Text(
                                'No PDF document uploaded for this customer.',
                                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.upload_file),
                                  label: const Text('UPLOAD PDF'),
                                  onPressed: _uploadCustomerPdf,
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Collapsible 4: Activity & History
                _buildCollapsibleSection(
                  title: 'Activity & History',
                  sectionKey: 'history',
                  child: historyAsync.when(
                    data: (history) {
                      if (history.isEmpty) return const Text('No activity history available.', style: TextStyle(color: Colors.grey));
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: history.length,
                        itemBuilder: (context, index) {
                          final h = history[index];
                          final staff = h['staff'] as Map<String, dynamic>?;
                          final staffName = staff?['name'] ?? 'System / Staff';
                          final photoUrl = staff?['profile_photo_url'] as String?;
                          final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
                          final title = h['title'] ?? (h['new_stage'] != null ? 'Advanced to ${h['new_stage']}' : 'Activity Logged');
                          final isDelivery = (h['action'] as String? ?? '').contains('delivery') || title.toLowerCase().contains('deliver');

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                              backgroundColor: hasPhoto ? Colors.transparent : (isDelivery ? Colors.green.shade50 : Colors.blue.shade50),
                              child: hasPhoto
                                  ? null
                                  : Icon(isDelivery ? Icons.local_shipping : Icons.history, size: 18, color: isDelivery ? Colors.green : Colors.blue),
                            ),
                            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('By $staffName • ${AppDateUtils.formatDateTime(h['created_at'])}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error loading history: $e'),
                  ),
                ),
              ],
            ),
          );
        },
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

  Widget _buildRtsDetailsSection() {
    final refNo = _customerData['reference'] ?? 'N/A';
    final remarks = _customerData['remarks'] ?? 'No remarks';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.electric_meter_outlined, color: Colors.teal),
                const SizedBox(width: 8),
                const Text('RTS DETAILS & METER STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Reference Number: $refNo'),
            Text('RTS Status: ${StageConfig.isCompleted(_currentStage) ? "Completed" : "In Progress"}'),
            if (remarks.isNotEmpty && remarks != 'No remarks') Text('Remarks: $remarks'),
          ],
        ),
      ),
    );
  }

  Widget _buildSubsidyDetailsSection() {
    final pmAppId = _customerData['pm_surya_ghar_application_id'] ?? 'N/A';
    final remarks = _customerData['remarks'] ?? 'No remarks';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFFBC02D)),
                const SizedBox(width: 8),
                const Text('SUBSIDY APPLICATION & STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFBC02D))),
              ],
            ),
            const SizedBox(height: 12),
            Text('Application ID: $pmAppId'),
            Text('Subsidy Status: ${StageConfig.isCompleted(_currentStage) ? "Approved & Released" : "Processing"}'),
            if (remarks.isNotEmpty && remarks != 'No remarks') Text('Remarks: $remarks'),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required String sectionKey,
    required Widget child,
  }) {
    final isExpanded = _expandedSection == sectionKey;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              setState(() {
                _expandedSection = isExpanded ? null : sectionKey;
              });
            },
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            trailing: Icon(
              isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              color: Colors.blueGrey,
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: child,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
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

// ─── Installation Summary Card (Structure, Wiring, Panel) ────────────────────
class _InstallationSummaryCard extends ConsumerWidget {
  final String customerId;
  final String customerName;
  final String role;

  const _InstallationSummaryCard({
    required this.customerId,
    required this.customerName,
    required this.role,
  });

  String _normalizeTaskTypeForDb(String type) {
    final t = type.toLowerCase();
    if (t.contains('structure')) return 'Structure Installation';
    if (t.contains('wiring')) return 'Wiring';
    if (t.contains('panel')) return 'Panel Uploading';
    return type;
  }

  String _taskDisplayName(String type) {
    final t = type.toLowerCase();
    if (t.contains('structure')) return '1. Structure Installation';
    if (t.contains('wiring')) return '2. Wiring Installation';
    if (t.contains('panel')) return '3. Panel Installation';
    return type;
  }

  IconData _taskIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('structure')) return Icons.foundation_outlined;
    if (t.contains('wiring')) return Icons.electrical_services_outlined;
    if (t.contains('panel')) return Icons.solar_power_outlined;
    return Icons.build_circle_outlined;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Colors.green;
      case 'in progress': return Colors.orange.shade700;
      default: return Colors.grey;
    }
  }

  Future<void> _updateTaskStatus(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> task,
    String newStatus,
  ) async {
    final supabase = ref.read(supabaseClientProvider);
    final taskId = task['id']?.toString();
    final rawTaskType = task['task_type']?.toString() ?? 'Task';
    final dbTaskType = _normalizeTaskTypeForDb(rawTaskType);

    try {
      if (taskId != null && !taskId.startsWith('temp_')) {
        await supabase
            .from('site_installation_tasks')
            .update({'status': newStatus})
            .eq('id', taskId);
      } else {
        await supabase
            .from('site_installation_tasks')
            .upsert({
              'customer_id': customerId,
              'task_type': dbTaskType,
              'status': newStatus,
            }, onConflict: 'customer_id, task_type');
      }

      ref.invalidate(installationTasksProvider(customerId));
      ref.invalidate(customerListProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_taskDisplayName(dbTaskType)} updated to $newStatus'),
            backgroundColor: newStatus == 'Completed' ? Colors.green : Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(installationTasksProvider(customerId));

    return tasksAsync.when(
      data: (tasks) {
        final completedCount = tasks.where((t) => (t['status']?.toString().toLowerCase() == 'completed')).length;
        final progress = (completedCount / 3.0).clamp(0.0, 1.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress Bar Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Installation Sub-Stages',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: completedCount == 3 ? Colors.green.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: completedCount == 3 ? Colors.green.shade300 : Colors.blue.shade300,
                    ),
                  ),
                  child: Text(
                    '$completedCount / 3 Completed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: completedCount == 3 ? Colors.green.shade800 : Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  completedCount == 3 ? Colors.green : Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // The 3 Sub-stages: Structure, Wiring, Panel
            ...tasks.map((task) {
              final type = task['task_type']?.toString() ?? 'Task';
              final status = task['status']?.toString() ?? 'Not Started';
              final isDone = status.toLowerCase() == 'completed';
              final isInProgress = status.toLowerCase() == 'in progress';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                color: isDone
                    ? Colors.green.shade50.withValues(alpha: 0.5)
                    : (isInProgress ? Colors.orange.shade50.withValues(alpha: 0.4) : Colors.grey.shade50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDone
                        ? Colors.green.shade200
                        : (isInProgress ? Colors.orange.shade200 : Colors.grey.shade300),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_taskIcon(type), color: _statusColor(status), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _taskDisplayName(type),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _statusColor(status),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Action popup/buttons to change status
                      PopupMenuButton<String>(
                        tooltip: 'Change Status',
                        icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                        onSelected: (newStat) => _updateTaskStatus(context, ref, task, newStat),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'Not Started', child: Text('⚪ Not Started')),
                          const PopupMenuItem(value: 'In Progress', child: Text('🟡 In Progress')),
                          const PopupMenuItem(value: 'Completed', child: Text('🟢 Completed')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error loading installation sub-stages: $e'),
    );
  }
}

