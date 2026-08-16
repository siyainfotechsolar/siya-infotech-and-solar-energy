import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../tasks/ui/task_file_viewer_screen.dart';

class CustomerAdminPhotosWidget extends ConsumerStatefulWidget {
  final String customerId;

  const CustomerAdminPhotosWidget({super.key, required this.customerId});

  @override
  ConsumerState<CustomerAdminPhotosWidget> createState() => _CustomerAdminPhotosWidgetState();
}

class _CustomerAdminPhotosWidgetState extends ConsumerState<CustomerAdminPhotosWidget> {
  bool _isLoading = true;
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
          .eq('customer_id', widget.customerId)
          .eq('file_type', 'photo')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _photos = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    try {
      final d = DateTime.parse(dateTimeStr).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
      final amPm = d.hour >= 12 ? 'PM' : 'AM';
      final minutesStr = d.minute.toString().padLeft(2, '0');
      return '${d.day} ${months[d.month - 1]} ${d.year}, $hour:$minutesStr $amPm';
    } catch (_) {
      return dateTimeStr;
    }
  }

  String _formatRoleLabel(String? role) {
    switch (role) {
      case 'admin': return 'Admin';
      case 'office_staff': return 'Office Staff';
      case 'installer': return 'Structure Installer';
      case 'wireman': return 'Wireman';
      case 'supervisor': return 'Supervisor';
      case 'delivery_staff': return 'Delivery Staff';
      default: return role ?? 'Staff';
    }
  }

  Widget _buildPhotoGroup(String title, IconData icon, Color color, List<Map<String, dynamic>> groupPhotos) {
    if (groupPhotos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text('${groupPhotos.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: groupPhotos.length,
            itemBuilder: (context, index) {
              final photo = groupPhotos[index];
              final path = photo['file_path'] as String;
              final name = photo['file_name'] as String;
              final photoType = (photo['photo_type'] as String? ?? 'photo').replaceAll('_', ' ').toUpperCase();
              final staffObj = photo['staff'] as Map?;
              final uploaderName = (staffObj?['name'] as String?) ?? 'Staff';
              final uploaderRole = _formatRoleLabel(staffObj?['role'] as String?);
              final createdAt = _formatDate(photo['created_at']);

              final supabase = ref.read(supabaseClientProvider);
              final photoUrl = supabase.storage.from('task_attachments').getPublicUrl(path);

              return Container(
                margin: const EdgeInsets.only(right: 12),
                width: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                  color: Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => TaskFileViewerScreen(name: name, url: photoUrl)),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                          child: Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade100,
                              child: const Icon(Icons.image, color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            photoType,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$uploaderName ($uploaderRole)',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            createdAt,
                            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_photos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No installation photos uploaded yet for this customer.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final structurePhotos = _photos.where((p) => p['photo_type'] == 'structure').toList();
    final panelPhotos = _photos.where((p) => p['photo_type'] == 'panel').toList();
    final electricalPhotos = _photos.where((p) => 
      ['dc_wiring', 'ac_wiring', 'inverter', 'earthing', 'acdb', 'dcdb', 'meter', 'electrical_completion'].contains(p['photo_type'])
    ).toList();
    final finalPhotos = _photos.where((p) => 
      ['final_installation', 'other'].contains(p['photo_type']) || p['photo_type'] == null
    ).toList();

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
                const Text('INSTALLATION & ELECTRICAL PHOTOS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                Text('${_photos.length} Total', style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 16),

            _buildPhotoGroup('STRUCTURE PHOTOS', Icons.grid_view_outlined, Colors.indigo, structurePhotos),
            _buildPhotoGroup('PANEL PHOTOS', Icons.wb_sunny_outlined, Colors.orange.shade800, panelPhotos),
            _buildPhotoGroup('ELECTRICAL PHOTOS', Icons.bolt, Colors.blue.shade700, electricalPhotos),
            _buildPhotoGroup('FINAL & OTHER PHOTOS', Icons.check_circle_outline, Colors.green.shade700, finalPhotos),
          ],
        ),
      ),
    );
  }
}
