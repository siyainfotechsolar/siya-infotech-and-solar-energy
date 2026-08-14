import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/lead_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'add_lead_screen.dart';
import 'lead_details_screen.dart';

class LeadListScreen extends ConsumerStatefulWidget {
  const LeadListScreen({super.key});

  @override
  ConsumerState<LeadListScreen> createState() => _LeadListScreenState();
}

class _LeadListScreenState extends ConsumerState<LeadListScreen> {
  final Set<String> _selectedIds = {};

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete ${_selectedIds.length} leads?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );
    if (confirm != true) return;
    
    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.from('leads').delete().inFilter('id', _selectedIds.toList());
      setState(() => _selectedIds.clear());
      ref.invalidate(leadListProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leads deleted successfully')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadListProvider);
    final roleAsync = ref.watch(userRoleProvider);

    return Scaffold(
      appBar: _selectedIds.isNotEmpty
        ? AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selectedIds.clear()),
            ),
            title: Text('${_selectedIds.length} Selected'),
            actions: [
              roleAsync.when(
                data: (role) {
                  if (role == 'admin') {
                    return IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: _deleteSelected,
                    );
                  }
                  return const SizedBox.shrink();
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          )
        : AppBar(
            title: const Text('Leads'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AddLeadScreen()));
                },
              ),
            ],
          ),
      body: leadsAsync.when(
        data: (leads) {
          if (leads.isEmpty) return const Center(child: Text('No leads found.'));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(leadListProvider);
              await ref.read(leadListProvider.future);
            },
            child: ListView.builder(
              itemCount: leads.length,
              itemBuilder: (context, index) {
                final lead = leads[index];
                final isConverted = lead['status'] == 'converted';
                final isSelected = _selectedIds.contains(lead['id']);

                return Card(
                  color: isSelected ? Colors.blue.shade50 : null,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    selected: isSelected,
                    onLongPress: () {
                      roleAsync.whenData((role) {
                        if (role == 'admin') {
                          _toggleSelection(lead['id']);
                        }
                      });
                    },
                    onTap: () {
                      if (_selectedIds.isNotEmpty) {
                        _toggleSelection(lead['id']);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => LeadDetailsScreen(lead: lead)),
                        );
                      }
                    },
                    title: Text(lead['name'] ?? 'Unknown'),
                    subtitle: Text('${lead['village'] ?? 'Unknown'} • ${lead['mobile'] ?? 'Unknown'}'),
                    trailing: isConverted 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : (isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : const Icon(Icons.chevron_right)),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
