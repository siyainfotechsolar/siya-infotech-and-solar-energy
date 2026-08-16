import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/widgets/barcode_scanner_dialog.dart';
import '../../../../core/widgets/photo_upload_source_dialog.dart';
import '../../../../core/utils/activity_logger.dart';

/// Consolidated Installation Data Model
class ConsolidatedInstallationData {
  final String customerId;
  final String customerName;
  final String? pmAppId;
  final String systemCapacity;
  final String inverterSerial;
  final String? inverterPhotoUrl;
  final String meterNumber;
  final String generationReading;
  final String? generationTimestamp;
  final String? generationPhotoUrl;
  final double? geoLat;
  final double? geoLong;
  final String? geoTimestamp;
  final List<String> panelSerials;
  final List<Map<String, dynamic>> photos;

  ConsolidatedInstallationData({
    required this.customerId,
    required this.customerName,
    this.pmAppId,
    required this.systemCapacity,
    required this.inverterSerial,
    this.inverterPhotoUrl,
    required this.meterNumber,
    required this.generationReading,
    this.generationTimestamp,
    this.generationPhotoUrl,
    this.geoLat,
    this.geoLong,
    this.geoTimestamp,
    required this.panelSerials,
    required this.photos,
  });
}

/// 1. Compact Summary Card embedded in Customer Details Screen
class ConsolidatedInstallationSummaryCard extends ConsumerWidget {
  final Map<String, dynamic> customer;

  const ConsolidatedInstallationSummaryCard({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerId = customer['id']?.toString() ?? '';
    final systemCapacity = customer['system_size']?.toString() ?? '3.0 kW';

    return FutureBuilder<ConsolidatedInstallationData>(
      future: _fetchConsolidatedData(ref, customer),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        final panelCount = data?.panelSerials.length ?? 0;
        final inverterSerial = data?.inverterSerial.isNotEmpty == true ? data!.inverterSerial : 'Not Added';
        final meterNo = data?.meterNumber.isNotEmpty == true ? data!.meterNumber : 'Not Added';
        final generation = data?.generationReading.isNotEmpty == true ? '${data!.generationReading} Units' : 'Not Captured';
        final hasGeoTag = data?.geoLat != null && data?.geoLong != null;

        // Photo Counts by Category
        final photos = data?.photos ?? [];
        final panelPhotosCount = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'panel').length;
        final inverterPhotosCount = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'inverter').length;
        final genPhotosCount = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'generation').length;
        final geoPhotosCount = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'geo_tag' || (p['geo_lat'] != null)).length;
        final finalPhotosCount = photos.where((p) => ['final_installation', 'other', 'structure'].contains(p['photo_category'] ?? p['photo_type'])).length;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.bolt, color: Colors.orange, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'INSTALLATION SUMMARY',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                    if (hasGeoTag)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade300)),
                        child: const Row(
                          children: [
                            Icon(Icons.location_on, size: 12, color: Colors.green),
                            SizedBox(width: 4),
                            Text('📍 Geo-tagged', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ),
                  ],
                ),
                const Divider(height: 20),

                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  // Grid Summary
                  Row(
                    children: [
                      Expanded(
                        child: _summaryTile(Icons.power, 'System Capacity', systemCapacity, Colors.blue),
                      ),
                      Expanded(
                        child: _summaryTile(Icons.wb_sunny_outlined, 'Panel Serials', '$panelCount Scanned', Colors.orange.shade800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _summaryTile(Icons.bolt, 'Inverter Serial', inverterSerial, Colors.purple),
                      ),
                      Expanded(
                        child: _summaryTile(Icons.speed, 'Meter Number', meterNo, Colors.teal),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _summaryTile(Icons.bar_chart, 'Generation', generation, Colors.indigo),
                      ),
                      Expanded(
                        child: _summaryTile(
                          Icons.my_location,
                          'Geo-tag',
                          hasGeoTag ? '✓ Captured' : 'Not Captured',
                          hasGeoTag ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Photos Counter Badges
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Photos Evidence:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _photoBadge('Panel', panelPhotosCount, Colors.orange.shade800),
                            _photoBadge('Inverter', inverterPhotosCount, Colors.purple),
                            _photoBadge('Generation', genPhotosCount, Colors.indigo),
                            _photoBadge('Geo-tag', geoPhotosCount, Colors.green),
                            _photoBadge('Final', finalPhotosCount, Colors.teal),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConsolidatedInstallationScreen(customer: customer, initialData: data),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.analytics_outlined, size: 18),
                      label: const Text('VIEW INSTALLATION DETAILS & PHOTOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryTile(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
                Text(
                  value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(
        '$label: $count',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// Helper function to fetch & consolidate installation data
Future<ConsolidatedInstallationData> _fetchConsolidatedData(WidgetRef ref, Map<String, dynamic> customer) async {
  final supabase = ref.read(supabaseClientProvider);
  final customerId = customer['id']?.toString() ?? '';

  String inverterSerial = customer['inverter_serial']?.toString() ?? '';
  String? inverterPhotoUrl;
  String meterNumber = customer['meter_number']?.toString() ?? '';
  String generationReading = customer['generation_reading']?.toString() ?? '';
  String? generationTimestamp;
  String? generationPhotoUrl;
  double? geoLat = (customer['geo_latitude'] as num?)?.toDouble();
  double? geoLong = (customer['geo_longitude'] as num?)?.toDouble();
  String? geoTimestamp = customer['geo_timestamp']?.toString();
  List<String> panelSerials = [];

  // Parse customer panel serials if available
  final cSerials = customer['panel_serial_numbers'] ?? customer['panel_serials'];
  if (cSerials is List) {
    panelSerials = cSerials.map((e) => e.toString()).toList();
  }

  // Fetch tasks linked to customer to consolidate Wireman / Installer inputs
  try {
    final tasksRes = await supabase
        .from('tasks')
        .select()
        .eq('customer_id', customerId);

    final tasksList = List<Map<String, dynamic>>.from(tasksRes);

    for (final task in tasksList) {
      if (inverterSerial.isEmpty && task['inverter_serial'] != null) {
        inverterSerial = task['inverter_serial'].toString();
      }
      if (inverterPhotoUrl == null && task['inverter_photo_url'] != null) {
        inverterPhotoUrl = task['inverter_photo_url'].toString();
      }
      if (meterNumber.isEmpty && task['meter_number'] != null) {
        meterNumber = task['meter_number'].toString();
      }
      if (generationReading.isEmpty && task['generation_reading'] != null) {
        generationReading = task['generation_reading'].toString();
      }
      if (generationPhotoUrl == null && task['generation_photo_url'] != null) {
        generationPhotoUrl = task['generation_photo_url'].toString();
      }
      if (geoLat == null && task['geo_latitude'] != null) {
        geoLat = (task['geo_latitude'] as num).toDouble();
        geoLong = (task['geo_longitude'] as num).toDouble();
        geoTimestamp = task['geo_timestamp']?.toString();
      }
      if (panelSerials.isEmpty) {
        final tSerials = task['panel_serials'] ?? task['panel_serial_numbers'];
        if (tSerials is List) {
          panelSerials = tSerials.map((e) => e.toString()).toList();
        }
      }
    }
  } catch (_) {}

  // Fetch attachments (photos) from task_attachments
  List<Map<String, dynamic>> photos = [];
  try {
    final photoRes = await supabase
        .from('task_attachments')
        .select('*, staff:uploaded_by(name, role)')
        .eq('customer_id', customerId)
        .eq('file_type', 'photo')
        .order('created_at', ascending: false);

    photos = List<Map<String, dynamic>>.from(photoRes);
  } catch (_) {
    // Try fallback query by task_id
    try {
      final photoRes = await supabase
          .from('task_attachments')
          .select('*, staff:uploaded_by(name, role)')
          .eq('file_type', 'photo')
          .order('created_at', ascending: false);
      photos = List<Map<String, dynamic>>.from(photoRes);
    } catch (_) {}
  }

  // Deduplicate photos by file_path or id
  final seenPaths = <String>{};
  final deduplicatedPhotos = <Map<String, dynamic>>[];
  for (final photo in photos) {
    final path = photo['file_path']?.toString() ?? photo['id']?.toString() ?? '';
    if (!seenPaths.contains(path)) {
      seenPaths.add(path);
      deduplicatedPhotos.add(photo);
    }
  }

  return ConsolidatedInstallationData(
    customerId: customerId,
    customerName: customer['name']?.toString() ?? 'Customer',
    pmAppId: customer['pm_surya_ghar_application_id']?.toString(),
    systemCapacity: customer['system_size']?.toString() ?? '3.0 kW',
    inverterSerial: inverterSerial,
    inverterPhotoUrl: inverterPhotoUrl,
    meterNumber: meterNumber,
    generationReading: generationReading,
    generationTimestamp: generationTimestamp,
    generationPhotoUrl: generationPhotoUrl,
    geoLat: geoLat,
    geoLong: geoLong,
    geoTimestamp: geoTimestamp,
    panelSerials: panelSerials,
    photos: deduplicatedPhotos,
  );
}

/// 2. Full Consolidated Installation Screen
class ConsolidatedInstallationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> customer;
  final ConsolidatedInstallationData? initialData;

  const ConsolidatedInstallationScreen({
    super.key,
    required this.customer,
    this.initialData,
  });

  @override
  ConsumerState<ConsolidatedInstallationScreen> createState() => _ConsolidatedInstallationScreenState();
}

class _ConsolidatedInstallationScreenState extends ConsumerState<ConsolidatedInstallationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ConsolidatedInstallationData? _data;
  bool _isLoading = true;
  String _selectedPhotoCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _data = widget.initialData;
    _refreshData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    final res = await _fetchConsolidatedData(ref, widget.customer);
    if (mounted) {
      setState(() {
        _data = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _uploadInstallationPhoto(String photoTypeKey, String categoryDisplayName) async {
    final user = ref.read(currentUserProvider);
    final profile = ref.read(currentStaffProfileProvider).value;
    final role = profile?['role']?.toString().toLowerCase();

    if (role == 'delivery_staff') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery Staff is not authorized to upload installation photos.')),
      );
      return;
    }

    final result = await PhotoUploadSourceDialog.selectAndProcessPhoto(
      context,
      categoryTitle: categoryDisplayName,
      requireGeoTag: photoTypeKey == 'geo_tag',
    );

    if (result == null) return;

    try {
      setState(() => _isLoading = true);
      final bytes = await result.file.readAsBytes();
      final uploaderName = (profile?['name'] as String?) ?? user?.email ?? 'Staff';
      final uploaderRole = (profile?['role'] as String?) ?? 'Staff';
      final staffCategory = (profile?['designation'] as String?) ?? uploaderRole;
      final supabase = ref.read(supabaseClientProvider);
      final customerId = widget.customer['id'] ?? widget.customer['customer_id'];

      final fileName = result.file.path.split('/').last.split('\\').last;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final uploadPath = 'installation/$customerId/${photoTypeKey}_${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await supabase.storage.from('task_attachments').uploadBinary(
        uploadPath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      try {
        await supabase.from('task_attachments').insert({
          'customer_id': customerId,
          'file_name': safeName,
          'file_path': uploadPath,
          'file_type': 'photo',
          'photo_type': photoTypeKey,
          'photo_category': photoTypeKey,
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
          'customer_id': customerId,
          'file_name': safeName,
          'file_path': uploadPath,
          'file_type': 'photo',
          'photo_type': photoTypeKey,
          'file_size': bytes.length,
          'uploaded_by': user?.id,
        });
      }

      // Log Activity Feed
      await ActivityLogger.log(
        supabase: supabase,
        customerId: customerId.toString(),
        action: 'INSTALLATION_PHOTO_UPLOADED',
        description: '$uploaderName ($uploaderRole) uploaded $categoryDisplayName Photo',
        performedBy: user?.id,
      );

      await _refreshData();

      if (mounted) {
        final gpsMsg = result.hasGps ? '\n📍 Geo-tagged (${result.gpsSource})' : '\n⚠ No GPS';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$categoryDisplayName photo uploaded by $uploaderName!$gpsMsg'),
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

  void _openGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerName = widget.customer['name'] ?? 'Customer';
    final customerId = widget.customer['customer_id'] ?? widget.customer['id'] ?? '';
    final pmAppId = widget.customer['pm_surya_ghar_application_id'] ?? 'N/A';
    final systemCapacity = _data?.systemCapacity ?? widget.customer['system_size'] ?? '3 kW';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('INSTALLATION EVIDENCE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('$customerName • $systemCapacity', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Evidence',
            onPressed: _refreshData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.photo_library, size: 18), text: 'PHOTOS'),
            Tab(icon: Icon(Icons.wb_sunny, size: 18), text: 'PANEL SERIALS'),
            Tab(icon: Icon(Icons.bolt, size: 18), text: 'INVERTER'),
            Tab(icon: Icon(Icons.speed, size: 18), text: 'METER'),
            Tab(icon: Icon(Icons.bar_chart, size: 18), text: 'GENERATION'),
            Tab(icon: Icon(Icons.location_on, size: 18), text: 'GEO-TAG'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPhotosTab(),
                _buildPanelSerialsTab(),
                _buildInverterTab(),
                _buildMeterTab(),
                _buildGenerationTab(),
                _buildGeoTagTab(),
              ],
            ),
    );
  }

  // --- TAB 1: CONSOLIDATED PHOTOS GALLERY ---
  Widget _buildPhotosTab() {
    final photos = _data?.photos ?? [];

    if (photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('No installation photos uploaded yet.', style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Photos uploaded by Wireman, Installer, Admin, or Supervisor will appear here.', style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final categories = ['ALL', 'PANEL', 'INVERTER', 'GENERATION', 'GEO-TAG', 'FINAL / OTHER'];

    List<Map<String, dynamic>> filteredPhotos = photos;
    if (_selectedPhotoCategory == 'PANEL') {
      filteredPhotos = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'panel').toList();
    } else if (_selectedPhotoCategory == 'INVERTER') {
      filteredPhotos = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'inverter').toList();
    } else if (_selectedPhotoCategory == 'GENERATION') {
      filteredPhotos = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'generation').toList();
    } else if (_selectedPhotoCategory == 'GEO-TAG') {
      filteredPhotos = photos.where((p) => (p['photo_category'] ?? p['photo_type']) == 'geo_tag' || p['geo_lat'] != null).toList();
    } else if (_selectedPhotoCategory == 'FINAL / OTHER') {
      filteredPhotos = photos.where((p) => ['final_installation', 'other', 'structure'].contains(p['photo_category'] ?? p['photo_type'])).toList();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: const Text('+ UPLOAD INSTALLATION PHOTO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: () => _uploadInstallationPhoto('installation', 'Installation'),
            ),
          ),
          const SizedBox(height: 14),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSel = _selectedPhotoCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                    selected: isSel,
                    selectedColor: Colors.blue.shade800,
                    onSelected: (_) => setState(() => _selectedPhotoCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CONSOLIDATED PHOTOS (${filteredPhotos.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
              const Text('Source-Attributed', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.82,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: filteredPhotos.length,
            itemBuilder: (context, index) {
              final photo = filteredPhotos[index];
              return _buildPhotoGridCard(photo);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGridCard(Map<String, dynamic> photo) {
    final supabase = ref.read(supabaseClientProvider);
    final path = photo['file_path'] as String? ?? '';
    final photoUrl = supabase.storage.from('task_attachments').getPublicUrl(path);
    final typeStr = (photo['photo_category'] ?? photo['photo_type'] ?? 'PHOTO').toString().replaceAll('_', ' ').toUpperCase();
    final staffObj = photo['staff'] as Map?;
    final uploaderName = (staffObj?['name'] as String?) ?? 'Staff';
    final uploaderRole = _formatRole(staffObj?['role'] as String?);
    final hasGeo = photo['geo_lat'] != null && photo['geo_long'] != null;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showPhotoDetailModal(photo, photoUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                      child: Text(typeStr, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (hasGeo)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.location_on, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$uploaderName ($uploaderRole)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_formatDateTime(photo['created_at']), style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 2: PANEL SERIAL NUMBERS ---
  Widget _buildPanelSerialsTab() {
    final serials = _data?.panelSerials ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.wb_sunny_outlined, color: Colors.orange.shade800, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Panel Quantity: ${serials.length}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                        const Text('Scanned via Barcode/QR or Manual Entry', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _openPanelScannerDialog,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                    icon: const Icon(Icons.qr_code_scanner, size: 16),
                    label: const Text('ADD SERIAL'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text('SCANNED PANEL SERIAL NUMBERS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
          const SizedBox(height: 8),

          if (serials.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No panel serial numbers scanned yet.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: serials.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                    ),
                    title: Text(serials[index], style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 15)),
                    subtitle: const Text('Verified Panel Serial', style: TextStyle(fontSize: 11, color: Colors.green)),
                    trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // --- TAB 3: INVERTER DETAILS ---
  Widget _buildInverterTab() {
    final invSerial = _data?.inverterSerial ?? 'Not Added';
    final invPhotoUrl = _data?.inverterPhotoUrl;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.bolt, color: Colors.purple, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('INVERTER SERIAL NUMBER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(invSerial, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  const Text('Inverter Specifications (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  _specRow('Brand:', 'Standard (Optional)'),
                  _specRow('Model:', 'Standard (Optional)'),
                  _specRow('Wattage Rating:', '3.0 kW (Optional)'),
                  const SizedBox(height: 16),

                  if (invPhotoUrl != null && invPhotoUrl.isNotEmpty) ...[
                    const Text('INVERTER PHOTO EVIDENCE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        invPhotoUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(height: 120, color: Colors.grey.shade200, child: const Center(child: Text('Image unavailable'))),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700, foregroundColor: Colors.white),
                      icon: const Icon(Icons.add_a_photo, size: 16),
                      label: const Text('+ UPLOAD INVERTER PHOTO'),
                      onPressed: () => _uploadInstallationPhoto('inverter', 'Inverter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 4: METER DETAILS ---
  Widget _buildMeterTab() {
    final meterNo = _data?.meterNumber ?? 'Not Added';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.speed, color: Colors.teal, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('METER SERIAL NUMBER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(meterNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(child: Text('Separate meter photo is not mandatory for installation identification.', style: TextStyle(fontSize: 11, color: Colors.blue))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
                      icon: const Icon(Icons.add_a_photo, size: 16),
                      label: const Text('+ UPLOAD METER PHOTO'),
                      onPressed: () => _uploadInstallationPhoto('meter', 'Meter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 5: GENERATION DETAILS ---
  Widget _buildGenerationTab() {
    final genReading = _data?.generationReading ?? 'Not Captured';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.bar_chart, color: Colors.indigo, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('GENERATION READING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(genReading != 'Not Captured' ? '$genReading Units' : genReading, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
                      icon: const Icon(Icons.add_a_photo, size: 16),
                      label: const Text('+ UPLOAD GENERATION PHOTO'),
                      onPressed: () => _uploadInstallationPhoto('generation', 'Generation'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 6: GEO-TAG DETAILS ---
  Widget _buildGeoTagTab() {
    final lat = _data?.geoLat;
    final lng = _data?.geoLong;
    final timestamp = _data?.geoTimestamp;
    final hasGeo = lat != null && lng != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: hasGeo ? Colors.green.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.my_location, color: hasGeo ? Colors.green : Colors.grey, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('INSTALLATION GEO-TAG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(
                            hasGeo ? '📍 ${lat.toStringAsFixed(4)}° N, ${lng.toStringAsFixed(4)}° E' : 'Not Captured',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: hasGeo ? Colors.green.shade800 : Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  if (hasGeo) ...[
                    _specRow('Latitude:', lat.toString()),
                    _specRow('Longitude:', lng.toString()),
                    if (timestamp != null) _specRow('Captured Date & Time:', _formatDateTime(timestamp)),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _openGoogleMaps(lat, lng),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                        icon: const Icon(Icons.map, size: 18),
                        label: const Text('OPEN IN GOOGLE MAPS'),
                      ),
                    ),
                  ] else ...[
                    const Text('No geo-tag captured during installation.', style: TextStyle(color: Colors.grey)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                      icon: const Icon(Icons.location_on, size: 16),
                      label: const Text('📍 CAPTURE GEO-TAG PHOTO'),
                      onPressed: () => _uploadInstallationPhoto('geo_tag', 'Geo-Tag'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(Map<String, dynamic> photo, String photoUrl) {
    final typeStr = (photo['photo_category'] ?? photo['photo_type'] ?? 'PHOTO').toString().replaceAll('_', ' ').toUpperCase();
    final staffObj = photo['staff'] as Map?;
    final uploaderName = (photo['uploaded_by_name'] as String?) ?? (staffObj?['name'] as String?) ?? 'Staff';
    final rawRole = (photo['uploaded_by_role'] as String?) ?? (staffObj?['role'] as String?);
    final uploaderRole = _formatRole(rawRole);
    final sourceStr = (photo['source'] ?? photo['photo_source']) == 'APP_CAMERA' ? 'Camera' : ((photo['source'] ?? photo['photo_source']) == 'GALLERY' ? 'Gallery' : 'Camera');
    final hasGeo = photo['geo_lat'] != null && photo['geo_long'] != null;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showPhotoDetailModal(photo, photoUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                      child: Text(typeStr, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (hasGeo)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.location_on, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Uploaded by: $uploaderName', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('Role: $uploaderRole', style: TextStyle(fontSize: 9, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_formatDateTime(photo['captured_at'] ?? photo['created_at']), style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoDetailModal(Map<String, dynamic> photo, String photoUrl) {
    final typeStr = (photo['photo_category'] ?? photo['photo_type'] ?? 'PHOTO').toString().replaceAll('_', ' ').toUpperCase();
    final staffObj = photo['staff'] as Map?;
    final uploaderName = (photo['uploaded_by_name'] as String?) ?? (staffObj?['name'] as String?) ?? 'Staff';
    final rawRole = (photo['uploaded_by_role'] as String?) ?? (staffObj?['role'] as String?);
    final uploaderRole = _formatRole(rawRole);
    final staffCategory = (photo['uploaded_by_staff_category'] as String?) ?? (staffObj?['designation'] as String?) ?? uploaderRole;
    final createdAt = _formatDateTime(photo['captured_at'] ?? photo['created_at']);
    final sourceStr = (photo['source'] ?? photo['photo_source']) == 'APP_CAMERA' ? 'Camera' : ((photo['source'] ?? photo['photo_source']) == 'GALLERY' ? 'Gallery' : 'Camera');
    final gpsSourceRaw = photo['gps_source'] as String?;
    final gpsSourceStr = gpsSourceRaw == 'PHOTO_EXIF' ? 'Photo EXIF' : (gpsSourceRaw == 'CURRENT_DEVICE_GPS' ? 'Device GPS' : 'None');
    final lat = photo['geo_lat'] != null ? (photo['geo_lat'] as num).toDouble() : null;
    final lng = photo['geo_long'] != null ? (photo['geo_long'] as num).toDouble() : null;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.network(
                    photoUrl,
                    height: 240,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(typeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
                          if (lat != null && lng != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.shade300)),
                              child: const Text('✓ GPS Available', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade300)),
                              child: Text('⚠ GPS Not Available', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _detailRow('Photo Type:', typeStr),
                      _detailRow('Uploaded By:', uploaderName),
                      _detailRow('Role:', uploaderRole),
                      _detailRow('Category:', staffCategory),
                      _detailRow('Uploaded:', createdAt),
                      _detailRow('Source:', sourceStr),
                      _detailRow('GPS Source:', gpsSourceStr),
                      if (lat != null && lng != null) ...[
                        const SizedBox(height: 6),
                        Text('Latitude: ${lat.toStringAsFixed(6)}° N', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                        Text('Longitude: ${lng.toStringAsFixed(6)}° E', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _openGoogleMaps(lat, lng),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                            icon: const Icon(Icons.map, size: 14),
                            label: const Text('OPEN MAP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _openPanelScannerDialog() async {
    final scanned = await showDialog<String>(
      context: context,
      builder: (context) => const BarcodeScannerDialog(title: 'Scan Panel Serial'),
    );

    if (scanned != null && scanned.isNotEmpty) {
      final currentSerials = List<String>.from(_data?.panelSerials ?? []);
      if (currentSerials.contains(scanned)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Panel serial number already added.')),
          );
        }
        return;
      }
      currentSerials.add(scanned);
      // Save updated serials
      try {
        final supabase = ref.read(supabaseClientProvider);
        await supabase.from('customers').update({
          'panel_serial_numbers': currentSerials,
        }).eq('id', widget.customer['id']);

        _refreshData();
      } catch (_) {}
    }
  }

  Widget _specRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatRole(String? role) {
    switch (role) {
      case 'admin': return 'Admin';
      case 'wireman': return 'Wireman';
      case 'installer': return 'Installer';
      case 'supervisor': return 'Supervisor';
      default: return role ?? 'Staff';
    }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final d = DateTime.parse(dateStr).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
      final amPm = d.hour >= 12 ? 'PM' : 'AM';
      final minutesStr = d.minute.toString().padLeft(2, '0');
      return '${d.day} ${months[d.month - 1]} ${d.year}, $hour:$minutesStr $amPm';
    } catch (_) {
      return dateStr;
    }
  }
}
