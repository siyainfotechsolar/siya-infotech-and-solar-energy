import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/activity_logger.dart';

class CustomerMergeScreen extends ConsumerStatefulWidget {
  const CustomerMergeScreen({super.key});

  @override
  ConsumerState<CustomerMergeScreen> createState() => _CustomerMergeScreenState();
}

class _CustomerMergeScreenState extends ConsumerState<CustomerMergeScreen> {
  final _searchController1 = TextEditingController();
  final _searchController2 = TextEditingController();
  
  Map<String, dynamic>? _masterCustomer;
  Map<String, dynamic>? _duplicateCustomer;
  
  bool _isLoading = false;

  Future<void> _search(String query, bool isMaster) async {
    if (query.length < 3) return;
    
    final supabase = ref.read(supabaseClientProvider);
    final res = await supabase.from('customers').select().or('name.ilike.%$query%,mobile.ilike.%$query%,customer_id.ilike.%$query%').limit(1).maybeSingle();
    
    setState(() {
      if (isMaster) _masterCustomer = res;
      else _duplicateCustomer = res;
    });
  }

  Future<void> _merge() async {
    if (_masterCustomer == null || _duplicateCustomer == null) return;
    if (_masterCustomer!['id'] == _duplicateCustomer!['id']) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot merge a customer with themselves!')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Merge'),
        content: Text('Are you sure you want to merge ${_duplicateCustomer!['name']} into ${_masterCustomer!['name']}? This will move all tasks and history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('MERGE')),
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    
    try {
      final supabase = ref.read(supabaseClientProvider);
      final masterId = _masterCustomer!['id'];
      final duplicateId = _duplicateCustomer!['id'];

      // 1. Reassign Tasks
      await supabase.from('tasks').update({'customer_id': masterId}).eq('customer_id', duplicateId);
      
      // 2. Reassign History
      await supabase.from('stage_history').update({'customer_id': masterId}).eq('customer_id', duplicateId);
      
      // 3. Reassign Activity Logs
      await supabase.from('activity_log').update({'customer_id': masterId}).eq('customer_id', duplicateId);

      // 4. Delete Duplicate
      await supabase.from('customers').delete().eq('id', duplicateId);

      final user = ref.read(currentUserProvider);
      if (user != null) {
        try {
          final staffNameRes = await supabase.from('staff').select('name').eq('id', user.id).maybeSingle();
          final staffName = staffNameRes?['name'] ?? 'Staff member';
          await ActivityLogger.log(
            supabase: supabase,
            customerId: masterId,
            action: 'customers_merged',
            description: '$staffName merged duplicate customer ${_duplicateCustomer!['name']} into ${_masterCustomer!['name']}',
            performedBy: user.id,
          );
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customers merged successfully!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merge Customers')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('1. Select Master Customer (Will be kept)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController1,
              decoration: InputDecoration(
                hintText: 'Search Name or Mobile...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_searchController1.text, true),
                )
              ),
              onSubmitted: (val) => _search(val, true),
            ),
            if (_masterCustomer != null)
              Card(
                color: Colors.green.shade50,
                child: ListTile(
                  title: Text(_masterCustomer!['name']),
                  subtitle: Text('${_masterCustomer!['customer_id']} • ${_masterCustomer!['mobile']}'),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
              ),
            
            const SizedBox(height: 32),
            
            const Text('2. Select Duplicate (Will be archived/deleted)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController2,
              decoration: InputDecoration(
                hintText: 'Search Name or Mobile...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_searchController2.text, false),
                )
              ),
              onSubmitted: (val) => _search(val, false),
            ),
            if (_duplicateCustomer != null)
              Card(
                color: Colors.red.shade50,
                child: ListTile(
                  title: Text(_duplicateCustomer!['name']),
                  subtitle: Text('${_duplicateCustomer!['customer_id']} • ${_duplicateCustomer!['mobile']}'),
                  trailing: const Icon(Icons.warning, color: Colors.red),
                ),
              ),
              
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _masterCustomer != null && _duplicateCustomer != null && !_isLoading ? _merge : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('MERGE CUSTOMERS'),
            )
          ],
        ),
      ),
    );
  }
}
