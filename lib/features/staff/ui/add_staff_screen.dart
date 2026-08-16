import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' as io;
import '../../../core/constants/supabase_constants.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/utils/audit_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/notifications/notification_state.dart';
import '../../../core/notifications/notification_model.dart';
import '../../../core/widgets/unsaved_changes_scope.dart';
import '../../../core/utils/mobile_validator.dart';

class AddStaffScreen extends ConsumerStatefulWidget {
  final String? initialName;
  final String? initialMobile;
  final String? temporaryContactId;

  const AddStaffScreen({
    super.key,
    this.initialName,
    this.initialMobile,
    this.temporaryContactId,
  });

  @override
  ConsumerState<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends ConsumerState<AddStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'office_staff';

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
    _mobileController.text = widget.initialMobile ?? '';
  }
  String _status = 'active';
  bool _isLoading = false;
  XFile? _selectedImage;
  Uint8List? _imageBytes;

  Future<void> _pickImageSource(ImageSource source) async {
    try {
      final img = await ImagePicker().pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 400,
        maxHeight: 400,
      );
      if (img != null) {
        final bytes = await img.readAsBytes();
        setState(() {
          _selectedImage = img;
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      if (e.toString().contains('MissingPluginException') && source == ImageSource.gallery) {
        try {
          final result = await FilePicker.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          );
          if (result == null || result.files.isEmpty) return;
          final file = result.files.first;
          var bytes = file.bytes;
          final path = file.path;
          if (bytes == null && path != null && !kIsWeb) {
            bytes = await io.File(path).readAsBytes();
          }
          if (bytes != null) {
            setState(() {
              _selectedImage = XFile.fromData(bytes!, name: file.name);
              _imageBytes = bytes;
            });
          }
        } catch (ex) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File picker failed: $ex')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e. Try restarting the app.')),
          );
        }
      }
    }
  }

  void _pickImage() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Photo from Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageSource(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose Photo from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageSource(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveStaff() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final mainSupabase = ref.read(supabaseClientProvider);
      final email = _emailController.text.trim();

      // Check if staff already exists in public.staff
      final existingStaff = await mainSupabase
          .from('staff')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (existingStaff != null) {
        throw Exception('User with this email is already registered as staff.');
      }

      String? userId;
      
      // Try to get existing user ID from auth.users (in case they have auth but no public.staff row)
      final String? existingUserId = await mainSupabase.rpc('get_user_id_by_email', params: {
        'p_email': email,
      });

      if (existingUserId != null) {
        userId = existingUserId;
      } else {
        // Create a secondary client so we don't log out the admin
        final secondaryClient = SupabaseClient(
          SupabaseConstants.supabaseUrl,
          SupabaseConstants.supabaseAnonKey,
          authOptions: const AuthClientOptions(
            authFlowType: AuthFlowType.implicit,
          ),
        );

        try {
          final authResponse = await secondaryClient.auth.signUp(
            email: email,
            password: _passwordController.text,
          );
          userId = authResponse.user?.id;
        } finally {
          secondaryClient.dispose();
        }
      }

      if (userId == null) {
        throw Exception('Failed to create or find user in Auth.');
      }

      // 2. Upload Profile Picture if selected
      String? profilePhotoUrl;
      if (_selectedImage != null && _imageBytes != null) {
        final fileExtension = _selectedImage!.path.split('.').last;
        final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        final path = '$userId/$fileName';

        await mainSupabase.storage.from('avatars').uploadBinary(
          path,
          _imageBytes!,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );

        profilePhotoUrl = mainSupabase.storage.from('avatars').getPublicUrl(path);
      }

      final category = StaffCategory.fromRole(_role);
      final cleanMobile = MobileValidator.normalize(_mobileController.text);

      // 3. Insert into staff table
      await mainSupabase.from('staff').insert({
        'id': userId,
        'name': _nameController.text.trim(),
        'mobile': cleanMobile,
        'email': email,
        'role': _role,
        'category': category,
        'status': _status,
        'profile_photo_url': profilePhotoUrl,
      });

      // 4. Create default permissions for new staff
      final defaultPerms = StaffPermissions.getDefault(userId, category);
      final permService = ref.read(permissionServiceProvider);
      final currentUser = ref.read(currentUserProvider);
      await permService.saveStaffPermissions(defaultPerms, currentUser?.id ?? userId);

      await AuditLogger.log(
        supabase: mainSupabase,
        userId: currentUser?.id,
        action: 'STAFF_CREATED',
        module: 'staff',
        entityId: userId,
        details: {
          'name': _nameController.text.trim(),
          'role': _role,
          'category': category,
        },
      );

      try {
        final notificationRepo = ref.read(notificationRepositoryProvider);
        await notificationRepo.notifyAdmins(
          notificationType: NotificationType.staffCreated,
          title: '👥 New Staff Created',
          message: 'New staff member ${_nameController.text.trim()} ($_role) has been created.',
          relatedRecordId: userId,
        );
      } catch (_) {}

      if (widget.temporaryContactId != null) {
        await mainSupabase.from('temporary_contacts').delete().eq('id', widget.temporaryContactId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff created successfully!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isDirty =>
      _nameController.text.isNotEmpty ||
      _mobileController.text.isNotEmpty ||
      _emailController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesScope(
      isDirty: _isDirty,
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Staff')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: _imageBytes != null ? MemoryImage(_imageBytes!) : null,
                    backgroundColor: Colors.blue.shade50,
                    child: _imageBytes != null
                        ? null
                        : const Icon(Icons.add_a_photo, size: 32, color: Colors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileController,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                  prefixText: '+91 ',
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: MobileValidator.inputFormatters,
                validator: (val) => MobileValidator.validate(val, required: true),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Login / Email Address *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (val) => val == null || !val.contains('@') ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Temporary Password *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                validator: (val) => val == null || val.length < 6 ? 'Min 6 characters' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work_outline),
                ),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'office_staff', child: Text('Office Staff')),
                  DropdownMenuItem(value: 'installer', child: Text('Structure Installer')),
                  DropdownMenuItem(value: 'wireman', child: Text('Wireman / Electrical Installer')),
                  DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                  DropdownMenuItem(value: 'delivery_staff', child: Text('Delivery Staff')),
                ],
                onChanged: (val) => setState(() => _role = val!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.info_outline),
                ),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
                onChanged: (val) => setState(() => _status = val!),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveStaff,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('SAVE STAFF', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
