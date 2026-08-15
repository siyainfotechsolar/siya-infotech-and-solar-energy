import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../auth/providers/auth_provider.dart';

class TemporaryContactsScreen extends ConsumerStatefulWidget {
  const TemporaryContactsScreen({super.key});

  @override
  ConsumerState<TemporaryContactsScreen> createState() => _TemporaryContactsScreenState();
}

class _TemporaryContactsScreenState extends ConsumerState<TemporaryContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _allContacts = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchContacts() async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final response = await supabase
          .from('temporary_contacts')
          .select()
          .order('name');

      if (mounted) {
        setState(() {
          _allContacts = List<Map<String, dynamic>>.from(response);
          _filteredContacts = _allContacts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredContacts = _allContacts;
      } else {
        _filteredContacts = _allContacts.where((c) {
          final name = (c['name'] ?? '').toString().toLowerCase();
          final mobile = (c['mobile'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery) || mobile.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _callContact(String mobile) async {
    if (mobile.trim().isEmpty) return;
    final Uri telUri = Uri.parse('tel:$mobile');
    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch dialer';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error making call: $e')),
        );
      }
    }
  }

  Future<void> _shareContact(Map<String, dynamic> contact) async {
    final name = contact['name'] ?? 'N/A';
    final mobile = contact['mobile'] ?? 'N/A';
    final shareText = "Temporary Contact Info:\nName: $name\nMobile: $mobile";

    try {
      await SharePlus.instance.share(ShareParams(text: shareText));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: shareText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact details copied to clipboard!')),
        );
      }
    }
  }

  Future<void> _showAddEditContactDialog({Map<String, dynamic>? contact}) async {
    final isEdit = contact != null;
    final nameController = TextEditingController(text: contact?['name']);
    final mobileController = TextEditingController(text: contact?['mobile']);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isEdit ? 'Edit Contact' : 'Add Temporary Contact', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder()),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: mobileController,
                  decoration: const InputDecoration(labelText: 'Mobile Number *', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Required';
                    if (val.trim().length < 10) return 'Enter a valid 10-digit number';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final name = nameController.text.trim();
                  final mobile = mobileController.text.trim();
                  final messenger = ScaffoldMessenger.of(context);
                  
                  Navigator.pop(context);
                  setState(() => _isLoading = true);

                  try {
                    final supabase = ref.read(supabaseClientProvider);
                    if (isEdit) {
                      await supabase.from('temporary_contacts').update({
                        'name': name,
                        'mobile': mobile,
                        'updated_at': DateTime.now().toUtc().toIso8601String(),
                      }).eq('id', contact['id']);
                    } else {
                      await supabase.from('temporary_contacts').insert({
                        'name': name,
                        'mobile': mobile,
                      });
                    }
                    _fetchContacts();
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Failed to save: $e')),
                      );
                      setState(() => _isLoading = false);
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
  }

  Future<void> _deleteContact(Map<String, dynamic> contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Contact'),
          content: Text('Are you sure you want to delete contact for ${contact['name']}?'),
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
      setState(() => _isLoading = true);
      try {
        final supabase = ref.read(supabaseClientProvider);
        await supabase.from('temporary_contacts').delete().eq('id', contact['id']);
        _fetchContacts();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(userRoleProvider);
    final isAdmin = roleAsync.value == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('TEMPORARY STAFF', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search Name / Mobile',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
          // Contacts List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Error loading contacts: $_errorMessage',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                    : _filteredContacts.isEmpty
                        ? const Center(child: Text('No contacts found', style: TextStyle(color: Colors.grey, fontSize: 16)))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _filteredContacts.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final contact = _filteredContacts[index];
                              final name = contact['name'] ?? 'N/A';
                              final mobile = contact['mobile'] ?? 'N/A';

                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  subtitle: Text(mobile, style: const TextStyle(color: Colors.black54)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.phone_enabled, color: Colors.green),
                                        onPressed: () => _callContact(mobile),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.share_outlined, color: Colors.blue),
                                        onPressed: () => _shareContact(contact),
                                      ),
                                      if (isAdmin) ...[
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                                          onPressed: () => _showAddEditContactDialog(contact: contact),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                          onPressed: () => _deleteContact(contact),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _showAddEditContactDialog(),
              tooltip: 'Add Contact',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
