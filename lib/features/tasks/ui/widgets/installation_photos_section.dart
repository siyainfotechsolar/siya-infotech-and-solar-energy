import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/providers/auth_provider.dart';
import '../task_file_viewer_screen.dart';

class PhotoCategoryConfig {
  final String typeKey;
  final String displayName;
  final IconData icon;
  final String group; // 'structure', 'panel', 'electrical', 'final'

  const PhotoCategoryConfig({
    required this.typeKey,
    required this.displayName,
    required this.icon,
    required this.group,
  });
}

const List<PhotoCategoryConfig> kAllPhotoCategories = [
  PhotoCategoryConfig(typeKey: 'structure', displayName: 'Structure', icon: Icons.grid_view_outlined, group: 'structure'),
  PhotoCategoryConfig(typeKey: 'panel', displayName: 'Panel', icon: Icons.wb_sunny_outlined, group: 'panel'),
  PhotoCategoryConfig(typeKey: 'dc_wiring', displayName: 'DC Wiring', icon: Icons.cable, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'ac_wiring', displayName: 'AC Wiring', icon: Icons.alt_route, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'inverter', displayName: 'Inverter', icon: Icons.bolt, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'earthing', displayName: 'Earthing', icon: Icons.g_translate_outlined, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'acdb', displayName: 'ACDB', icon: Icons.developer_board, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'dcdb', displayName: 'DCDB', icon: Icons.memory, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'meter', displayName: 'Meter', icon: Icons.speed, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'final_installation', displayName: 'Final Installation', icon: Icons.check_circle_outline, group: 'final'),
  PhotoCategoryConfig(typeKey: 'other', displayName: 'Other', icon: Icons.more_horiz, group: 'final'),
];

class InstallationPhotosSection extends ConsumerStatefulWidget {
  final String taskId;
  final String customerId;
  final String userRole;

  const InstallationPhotosSection({
    super.key,
    required this.taskId,
    required this.customerId,
    required this.userRole,
  });

  @override
  ConsumerState<InstallationPhotosSection> createState() => _InstallationPhotosSectionState();
}

class _InstallationPhotosSectionState extends ConsumerState<InstallationPhotosSection> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _photos = [];

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
  }

  Future<void> _fetchPhotos() async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final res = await supabase
          .from('task_attachments')
          .select('*, staff:uploaded_by(name, role)')
          .eq('task_id', widget.taskId)
          .eq('file_type', 'photo')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _photos = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  List<PhotoCategoryConfig> _getAvailableCategories() {
    final role = widget.userRole;
    if (role == 'delivery_staff') {
      return []; // Delivery staff cannot upload installation photos
    }
    if (role == 'installer') {
      // Structure Installer
      return kAllPhotoCategories.where((c) => 
        c.typeKey == 'structure' || c.typeKey == 'panel' || c.typeKey == 'final_installation' || c.typeKey == 'other'
      ).toList();
    }
    // Wireman, Admin, Office Staff, Supervisor can see/upload all
    return kAllPhotoCategories;
  }

  Future<void> _pickAndUploadPhoto(PhotoCategoryConfig category) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('CAMERA', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('GALLERY', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      XFile? image;
      try {
        image = await ImagePicker().pickImage(source: source, imageQuality: 70);
      } catch (_) {
        // Fallback file picker for web/Windows compatibility
        final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          if (file.bytes != null) {
            image = XFile.fromData(file.bytes!, name: file.name);
          }
        }
      }

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final user = ref.read(currentUserProvider);
      final supabase = ref.read(supabaseClientProvider);

      setState(() => _isLoading = true);

      final safeName = image.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final uploadPath = '${widget.taskId}/${category.typeKey}_${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await supabase.storage.from('task_attachments').uploadBinary(
        uploadPath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      await supabase.from('task_attachments').insert({
        'task_id': widget.taskId,
        'customer_id': widget.customerId,
        'file_name': image.name,
        'file_path': uploadPath,
        'file_type': 'photo',
        'photo_type': category.typeKey,
        'file_size': bytes.length,
        'uploaded_by': user?.id,
      });

      await _fetchPhotos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${category.displayName} photo uploaded successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePhoto(String attachmentId, String filePath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Are you sure you want to delete this photo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.from('task_attachments').delete().eq('id', attachmentId);
      try {
        await supabase.storage.from('task_attachments').remove([filePath]);
      } catch (_) {}

      await _fetchPhotos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo deleted.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openFullPhoto(String fileName, String filePath) async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final url = supabase.storage.from('task_attachments').getPublicUrl(filePath);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskFileViewerScreen(name: fileName, url: url)),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userRole == 'delivery_staff') {
      return const SizedBox.shrink(); // Delivery staff cannot view/upload installation photos
    }

    final categories = _getAvailableCategories();
    final user = ref.read(currentUserProvider);
    final isAdmin = widget.userRole == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'INSTALLATION PHOTOS',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
            ),
            if (_isLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 8),

        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: categories.map((cat) {
                final categoryPhotos = _photos.where((p) => p['photo_type'] == cat.typeKey).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(cat.icon, size: 20, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cat.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isLoading ? null : () => _pickAndUploadPhoto(cat),
                          icon: const Icon(Icons.add_a_photo, size: 16),
                          label: const Text('+ ADD PHOTO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                        ),
                      ],
                    ),

                    if (categoryPhotos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: categoryPhotos.length,
                          itemBuilder: (context, idx) {
                            final photo = categoryPhotos[idx];
                            final path = photo['file_path'] as String;
                            final name = photo['file_name'] as String;
                            final supabase = ref.read(supabaseClientProvider);
                            final photoUrl = supabase.storage.from('task_attachments').getPublicUrl(path);
                            final canDelete = isAdmin || (user != null && user.id == photo['uploaded_by']);

                            return Container(
                              margin: const EdgeInsets.only(right: 12),
                              width: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => _openFullPhoto(name, path),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: Image.network(
                                        photoUrl,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Center(
                                          child: Icon(Icons.image, color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (canDelete)
                                    Positioned(
                                      top: 2, right: 2,
                                      child: GestureDetector(
                                        onTap: () => _deletePhoto(photo['id'], path),
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const Divider(height: 20),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
