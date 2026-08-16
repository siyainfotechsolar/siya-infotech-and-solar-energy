import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/providers/auth_provider.dart';
import '../task_file_viewer_screen.dart';
import '../../../../core/widgets/geo_tag_photo_capture_dialog.dart';
import '../../../../core/widgets/photo_upload_source_dialog.dart';
import '../../../../core/utils/activity_logger.dart';

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
  PhotoCategoryConfig(typeKey: 'inverter', displayName: 'Inverter', icon: Icons.bolt, group: 'electrical'),
  PhotoCategoryConfig(typeKey: 'electrical', displayName: 'Installation / Electrical Photo', icon: Icons.electrical_services, group: 'electrical'),
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
    final result = await PhotoUploadSourceDialog.selectAndProcessPhoto(
      context,
      categoryTitle: category.displayName,
      requireGeoTag: category.typeKey == 'geo_tag',
    );

    if (result == null) return;

    try {
      setState(() => _isLoading = true);
      final bytes = await result.file.readAsBytes();
      final user = ref.read(currentUserProvider);
      final profile = ref.read(currentStaffProfileProvider).value;
      final uploaderName = (profile?['name'] as String?) ?? user?.email ?? 'Staff';
      final uploaderRole = (profile?['role'] as String?) ?? 'Staff';
      final staffCategory = (profile?['designation'] as String?) ?? uploaderRole;
      final supabase = ref.read(supabaseClientProvider);

      final fileName = result.file.path.split('/').last.split('\\').last;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final uploadPath = '${widget.taskId}/${category.typeKey}_${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await supabase.storage.from('task_attachments').uploadBinary(
        uploadPath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      try {
        await supabase.from('task_attachments').insert({
          'task_id': widget.taskId,
          'customer_id': widget.customerId,
          'file_name': safeName,
          'file_path': uploadPath,
          'file_type': 'photo',
          'photo_type': category.typeKey,
          'photo_category': category.typeKey,
          'file_size': bytes.length,
          'uploaded_by': user?.id,
          'uploaded_by_user_id': user?.id,
          'uploaded_by_name': uploaderName,
          'uploaded_by_role': uploaderRole,
          'uploaded_by_staff_category': staffCategory,
          'source': result.source,
          'photo_source': result.source,
          'gps_source': result.gpsSource,
          'geo_lat': result.latitude,
          'geo_long': result.longitude,
          'geo_accuracy': result.accuracyMeters,
          'captured_at': result.capturedAt,
          'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {
        await supabase.from('task_attachments').insert({
          'task_id': widget.taskId,
          'customer_id': widget.customerId,
          'file_name': safeName,
          'file_path': uploadPath,
          'file_type': 'photo',
          'photo_type': category.typeKey,
          'file_size': bytes.length,
          'uploaded_by': user?.id,
        });
      }

      // Log Activity Feed
      await ActivityLogger.log(
        supabase: supabase,
        customerId: widget.customerId,
        action: 'INSTALLATION_PHOTO_UPLOADED',
        description: '$uploaderName ($uploaderRole) uploaded ${category.displayName} Photo',
        performedBy: user?.id,
      );

      await _fetchPhotos();

      if (mounted) {
        final gpsMsg = result.hasGps ? '\n📍 Geo-tagged (${result.gpsSource})' : '\n⚠ No GPS';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${category.displayName} photo uploaded by $uploaderName!$gpsMsg'),
            backgroundColor: result.hasGps ? Colors.green : Colors.blueGrey,
          ),
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

  Future<void> _captureGeoTagPhoto(PhotoCategoryConfig category) async {
    final result = await GeoTagPhotoCaptureDialog.startCapture(
      context,
      categoryTitle: category.displayName,
    );

    if (result == null) return;

    try {
      setState(() => _isLoading = true);
      final bytes = await result.file.readAsBytes();
      final user = ref.read(currentUserProvider);
      final profile = ref.read(currentStaffProfileProvider).value;
      final uploaderName = (profile?['name'] as String?) ?? user?.email ?? 'Staff';
      final uploaderRole = (profile?['role'] as String?) ?? 'Staff';
      final staffCategory = (profile?['designation'] as String?) ?? uploaderRole;
      final supabase = ref.read(supabaseClientProvider);

      final safeName = 'geotag_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final uploadPath = '${widget.taskId}/${category.typeKey}_${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await supabase.storage.from('task_attachments').uploadBinary(
        uploadPath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      try {
        await supabase.from('task_attachments').insert({
          'task_id': widget.taskId,
          'customer_id': widget.customerId,
          'file_name': safeName,
          'file_path': uploadPath,
          'file_type': 'photo',
          'photo_type': category.typeKey,
          'photo_category': category.typeKey,
          'file_size': bytes.length,
          'uploaded_by': user?.id,
          'uploaded_by_user_id': user?.id,
          'uploaded_by_name': uploaderName,
          'uploaded_by_role': uploaderRole,
          'uploaded_by_staff_category': staffCategory,
          'source': 'APP_CAMERA',
          'photo_source': 'APP_CAMERA',
          'gps_source': 'CURRENT_DEVICE_GPS',
          'geo_lat': result.latitude,
          'geo_long': result.longitude,
          'geo_accuracy': result.accuracyMeters,
          'captured_at': result.capturedAt,
          'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {
        await supabase.from('task_attachments').insert({
          'task_id': widget.taskId,
          'customer_id': widget.customerId,
          'file_name': safeName,
          'file_path': uploadPath,
          'file_type': 'photo',
          'photo_type': category.typeKey,
          'file_size': bytes.length,
          'uploaded_by': user?.id,
        });
      }

      // Log Activity Feed
      await ActivityLogger.log(
        supabase: supabase,
        customerId: widget.customerId,
        action: 'INSTALLATION_PHOTO_UPLOADED',
        description: '$uploaderName ($uploaderRole) uploaded Geo-Tag ${category.displayName} Photo',
        performedBy: user?.id,
      );

      await _fetchPhotos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 Geo-Tag ${category.displayName} Photo Uploaded by $uploaderName!\nLat: ${result.latitude.toStringAsFixed(4)}, Long: ${result.longitude.toStringAsFixed(4)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading geo-tag photo: $e')));
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isLoading ? null : () => _captureGeoTagPhoto(cat),
                              icon: const Icon(Icons.location_on, size: 13),
                              label: const Text('📍 GEO-TAG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: const Size(60, 30),
                              ),
                            ),
                            const SizedBox(width: 4),
                            TextButton.icon(
                              onPressed: _isLoading ? null : () => _pickAndUploadPhoto(cat),
                              icon: const Icon(Icons.add_a_photo, size: 13),
                              label: const Text('+ ADD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blue.shade700,
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                minimumSize: const Size(50, 30),
                              ),
                            ),
                          ],
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
