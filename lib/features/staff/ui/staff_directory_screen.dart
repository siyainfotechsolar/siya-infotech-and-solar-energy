import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../auth/providers/auth_provider.dart';
import 'add_staff_screen.dart';

class StaffDirectoryScreen extends ConsumerStatefulWidget {
  const StaffDirectoryScreen({super.key});

  @override
  ConsumerState<StaffDirectoryScreen> createState() => _StaffDirectoryScreenState();
}

class _StaffDirectoryScreenState extends ConsumerState<StaffDirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _allEntries = [];
  List<Map<String, dynamic>> _filteredEntries = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      
      // Fetch staff and temporary contacts in parallel
      final results = await Future.wait([
        supabase.from('staff').select('id, name, role, mobile, profile_photo_url').eq('status', 'active'),
        supabase.from('temporary_contacts').select('id, name, mobile'),
      ]);

      final staffList = List<Map<String, dynamic>>.from(results[0]).map((item) => {
        ...item,
        'type': 'staff',
      }).toList();

      final tempList = List<Map<String, dynamic>>.from(results[1]).map((item) => {
        ...item,
        'type': 'temporary',
      }).toList();

      // Normalize matching keys to detect duplicates
      final staffMobiles = staffList.map((s) => (s['mobile'] ?? '').toString().trim()).where((m) => m.isNotEmpty).toSet();
      final staffNames = staffList.map((s) => (s['name'] ?? '').toString().trim().toLowerCase()).where((n) => n.isNotEmpty).toSet();

      // Filter out temporary contacts that match existing staff
      final filteredTempList = tempList.where((t) {
        final mobile = (t['mobile'] ?? '').toString().trim();
        final name = (t['name'] ?? '').toString().trim().toLowerCase();
        return !staffMobiles.contains(mobile) && !staffNames.contains(name);
      }).toList();

      // Clean up duplicates in database asynchronously
      final duplicateTempIds = tempList
          .where((t) => staffMobiles.contains((t['mobile'] ?? '').toString().trim()) || staffNames.contains((t['name'] ?? '').toString().trim().toLowerCase()))
          .map((t) => t['id'] as String)
          .toList();

      if (duplicateTempIds.isNotEmpty) {
        supabase.from('temporary_contacts').delete().inFilter('id', duplicateTempIds).then((_) {});
      }

      if (mounted) {
        setState(() {
          _allEntries = [...staffList, ...filteredTempList];
          // Sort by name
          _allEntries.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
          _filteredEntries = _allEntries;
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
        _filteredEntries = _allEntries;
      } else {
        _filteredEntries = _allEntries.where((e) {
          final name = (e['name'] ?? '').toString().toLowerCase();
          final mobile = (e['mobile'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery) || mobile.contains(_searchQuery);
        }).toList();
      }
    });
  }

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Admin';
      case 'office_staff':
        return 'Office Staff';
      case 'installer':
        return 'Structure Installer';
      case 'wireman':
        return 'Wireman / Electrical Installer';
      case 'supervisor':
        return 'Supervisor';
      case 'delivery_staff':
        return 'Delivery Staff';
      default:
        return role;
    }
  }

  Future<void> _callEmployee(String mobile) async {
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

  Future<void> _shareEmployee(Map<String, dynamic> emp) async {
    final name = emp['name'] ?? 'N/A';
    final mobile = emp['mobile'] ?? 'N/A';
    final isStaff = emp['type'] == 'staff';
    final role = isStaff ? _formatRole(emp['role'] ?? '') : 'Temporary';

    final shareText = "Employee Details:\n"
        "Name: $name\n"
        "Type: $role\n"
        "Mobile: $mobile";

    try {
      await SharePlus.instance.share(ShareParams(text: shareText));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: shareText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Details copied to clipboard!')),
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
                    _fetchData();
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

  Future<void> _deleteTemporaryContact(Map<String, dynamic> contact) async {
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
        _fetchData();
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

  Future<void> _linkToStaff(Map<String, dynamic> tempContact) async {
    final supabase = ref.read(supabaseClientProvider);
    setState(() => _isLoading = true);

    try {
      final staffResponse = await supabase.from('staff').select('id, name, mobile, role').eq('status', 'active').order('name');
      final staffList = List<Map<String, dynamic>>.from(staffResponse);

      if (staffList.isEmpty) {
        throw 'No active staff accounts found to link.';
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      Map<String, dynamic>? selectedStaff;

      await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Link to Staff Account', style: TextStyle(fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Temporary Contact: ${tempContact['name']} (${tempContact['mobile']})'),
                    const SizedBox(height: 16),
                    const Text('Select Staff Account to link:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedStaff,
                      hint: const Text('Select Staff...'),
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: staffList.map((s) {
                        return DropdownMenuItem(
                          value: s,
                          child: Text('${s['name']} (${s['role']})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedStaff = val;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                  ElevatedButton(
                    onPressed: selectedStaff == null
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            setState(() => _isLoading = true);
                            try {
                              await supabase.from('staff').update({
                                'mobile': tempContact['mobile'],
                              }).eq('id', selectedStaff!['id']);

                              await supabase.from('temporary_contacts').delete().eq('id', tempContact['id']);

                              _fetchData();
                              
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Contacts linked successfully!'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                messenger.showSnackBar(SnackBar(content: Text('Failed to link: $e')));
                              }
                              _fetchData();
                            }
                          },
                    child: const Text('LINK'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_outlined),
                title: const Text('Add Staff / App User'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AddStaffScreen())).then((_) => _fetchData());
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Add Temporary Contact'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddEditContactDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(userRoleProvider);
    final isAdmin = roleAsync.value == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('EMPLOYEE DIRECTORY', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search box
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Error loading directory: $_errorMessage',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                    : _filteredEntries.isEmpty
                        ? const Center(
                            child: Text(
                              'No members found',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _filteredEntries.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final emp = _filteredEntries[index];
                              final name = emp['name'] ?? 'N/A';
                              final isStaff = emp['type'] == 'staff';
                              final role = isStaff ? _formatRole(emp['role'] ?? '') : 'Temporary';
                              final mobile = emp['mobile'] ?? 'N/A';
                              final photoUrl = isStaff ? emp['profile_photo_url'] as String? : null;
                              final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                                        backgroundColor: isStaff ? Colors.blue.shade50 : Colors.amber.shade50,
                                        child: hasPhoto
                                            ? null
                                            : Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: isStaff ? Colors.blue : Colors.amber.shade900,
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.circle,
                                                  size: 8,
                                                  color: isStaff ? Colors.green : Colors.amber,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isStaff ? '$role (App User)' : 'Temporary',
                                                  style: TextStyle(
                                                    color: isStaff ? Colors.green.shade700 : Colors.amber.shade800,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              mobile,
                                              style: const TextStyle(color: Colors.black54, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.phone_enabled, color: Colors.green),
                                            tooltip: 'Call',
                                            onPressed: () => _callEmployee(mobile),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.share_outlined, color: Colors.blue),
                                            tooltip: 'Share',
                                            onPressed: () => _shareEmployee(emp),
                                          ),
                                          if (isAdmin) ...[
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert),
                                              onSelected: (val) {
                                                if (val == 'edit') {
                                                  _showAddEditContactDialog(contact: emp);
                                                } else if (val == 'delete') {
                                                  _deleteTemporaryContact(emp);
                                                } else if (val == 'link') {
                                                  _linkToStaff(emp);
                                                } else if (val == 'convert') {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => AddStaffScreen(
                                                        initialName: emp['name'],
                                                        initialMobile: emp['mobile'],
                                                        temporaryContactId: emp['id'],
                                                      ),
                                                    ),
                                                  ).then((_) => _fetchData());
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                if (!isStaff) ...[
                                                  const PopupMenuItem(
                                                    value: 'convert',
                                                    child: Text('Convert to Staff'),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'link',
                                                    child: Text('Link to Staff'),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('Edit Contact'),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('Delete Contact'),
                                                  ),
                                                ],
                                                if (isStaff)
                                                  const PopupMenuItem(
                                                    enabled: false,
                                                    child: Text('Staff Account (Managed)'),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
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
              onPressed: _showAddOptions,
              tooltip: 'Add',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
