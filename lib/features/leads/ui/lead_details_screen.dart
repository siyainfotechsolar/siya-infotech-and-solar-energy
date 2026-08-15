import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customers/ui/customer_details_screen.dart';

class LeadDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> lead;
  
  const LeadDetailsScreen({super.key, required this.lead});

  @override
  ConsumerState<LeadDetailsScreen> createState() => _LeadDetailsScreenState();
}

class _LeadDetailsScreenState extends ConsumerState<LeadDetailsScreen> {
  bool _isConverting = false;

  Future<void> _convertToCustomer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Customer?'),
        content: const Text('This will create a new Customer record and mark this lead as converted. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('CONVERT')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isConverting = true);

    try {
      final supabase = ref.read(supabaseClientProvider);
      
      // 1. Check for duplicate mobile
      final duplicateCheck = await supabase
          .from('customers')
          .select('*')
          .eq('mobile', widget.lead['mobile'])
          .maybeSingle();
          
      if (duplicateCheck != null) {
        setState(() => _isConverting = false);
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('CUSTOMER ALREADY EXISTS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(duplicateCheck['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(duplicateCheck['customer_id'] ?? ''),
                  const SizedBox(height: 4),
                  Text(duplicateCheck['mobile'] ?? ''),
                  if (duplicateCheck['consumer_number'] != null) Text(duplicateCheck['consumer_number']),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close dialog
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: duplicateCheck)));
                  },
                  child: const Text('VIEW EXISTING'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 2. Generate Customer ID (Zero-padded C000XXX format)
      final countResp = await supabase.from('customers').select('id');
      final newIdNumber = (countResp as List).length + 1;
      final generatedId = 'C${newIdNumber.toString().padLeft(6, '0')}';

      final user = ref.read(currentUserProvider);
      
      // 3. Insert into Customers
      final insertedCustomer = await supabase.from('customers').insert({
        'customer_id': generatedId,
        'name': widget.lead['name'],
        'mobile': widget.lead['mobile'],
        'village': widget.lead['village'],
        'stage': 'PM Surya Ghar Application',
        'application_date': DateTime.now().toIso8601String().split('T').first,
        'created_by': user?.id,
      }).select().single();

      // 4. Update Lead Status
      await supabase.from('leads').update({'status': 'converted'}).eq('id', widget.lead['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully converted to Customer!')));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CustomerDetailsScreen(customer: insertedCustomer)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.lead['name'] ?? 'Lead Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Name: ${widget.lead['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Phone: ${widget.lead['mobile']}'),
                    Text('City/Village: ${widget.lead['village'] ?? 'N/A'}'),
                    Text('Source: ${widget.lead['source'] ?? 'N/A'}'),
                    Text('Status: ${(widget.lead['status'] ?? 'new').toUpperCase()}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (widget.lead['status'] != 'converted')
              ElevatedButton.icon(
                onPressed: _isConverting ? null : _convertToCustomer,
                icon: _isConverting ? const SizedBox.shrink() : const Icon(Icons.transform),
                label: _isConverting ? const CircularProgressIndicator() : const Text('CONVERT TO CUSTOMER'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
