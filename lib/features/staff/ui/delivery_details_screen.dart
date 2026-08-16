import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/notifications/notification_state.dart';
import '../../../core/notifications/notification_model.dart';
import '../../../core/utils/activity_logger.dart';
import '../../../core/utils/date_utils.dart';

class DeliveryDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> dispatch;

  const DeliveryDetailsScreen({super.key, required this.dispatch});

  @override
  ConsumerState<DeliveryDetailsScreen> createState() => _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends ConsumerState<DeliveryDetailsScreen> {
  bool _isLoading = false;
  PlatformFile? _pickedPhoto;
  String? _uploadedPhotoUrl;
  late String _status;

  @override
  void initState() {
    super.initState();
    _status = widget.dispatch['status'] ?? 'Pending';
    _uploadedPhotoUrl = widget.dispatch['photo_url'];
  }

  Future<void> _startDelivery() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);
      final dispatchId = widget.dispatch['id'];

      await supabase.from('material_dispatches').update({
        'status': 'Out for Delivery',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', dispatchId);

      final staffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
      final staffName = staffNameRes?['name'] ?? 'Delivery Staff';

      await ActivityLogger.log(
        supabase: supabase,
        customerId: widget.dispatch['customer_id'],
        action: 'delivery_started',
        description: '$staffName started delivery of ${widget.dispatch['material_name']} × ${widget.dispatch['quantity']}',
        performedBy: user?.id,
      );

      setState(() {
        _status = 'Out for Delivery';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery started! Out for Delivery.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedPhoto = result.files.first;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delivery photo attached!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error taking photo: $e')));
      }
    }
  }

  Future<void> _markDelivered() async {
    if (_pickedPhoto == null && _uploadedPhotoUrl == null) return;

    setState(() => _isLoading = true);
    final supabase = ref.read(supabaseClientProvider);
    final user = ref.read(currentUserProvider);
    final dispatchId = widget.dispatch['id'];
    final customer = widget.dispatch['customers'] ?? {};
    final customerName = customer['name'] ?? 'N/A';

    try {
      String? finalPhotoUrl = _uploadedPhotoUrl;

      // 1. Upload photo if picked
      if (_pickedPhoto != null && _pickedPhoto!.bytes != null) {
        final safeName = _pickedPhoto!.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final uploadPath = 'dispatches/$dispatchId/delivery_${DateTime.now().millisecondsSinceEpoch}_$safeName';

        await supabase.storage.from('task_attachments').uploadBinary(
          uploadPath,
          _pickedPhoto!.bytes!,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );

        finalPhotoUrl = supabase.storage.from('task_attachments').getPublicUrl(uploadPath);
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final formattedTime = AppDateUtils.formatDateTime(nowIso);

      // 2. Update dispatch status & delivered_at timestamp (with fallback if column not in DB yet)
      try {
        await supabase.from('material_dispatches').update({
          'status': 'Delivered',
          'photo_url': finalPhotoUrl,
          'delivered_at': nowIso,
          'updated_at': nowIso,
        }).eq('id', dispatchId);
      } catch (err) {
        if (err.toString().contains('delivered_at') || err.toString().contains('PGRST204')) {
          await supabase.from('material_dispatches').update({
            'status': 'Delivered',
            'photo_url': finalPhotoUrl,
            'updated_at': nowIso,
          }).eq('id', dispatchId);
        } else {
          rethrow;
        }
      }

      // 3. Notify Admin users via Edge Function (bypasses RLS & triggers FCM push)
      final staffNameRes = await supabase.from('staff').select('name').eq('id', user?.id ?? '').maybeSingle();
      final staffName = staffNameRes?['name'] ?? 'Delivery Staff';

      // 4. Log to Activity Feed with timestamp
      await ActivityLogger.log(
        supabase: supabase,
        customerId: widget.dispatch['customer_id'],
        action: 'delivery_completed',
        description: '$staffName completed delivery of ${widget.dispatch['material_name']} × ${widget.dispatch['quantity']} on $formattedTime',
        performedBy: user?.id,
      );

      final notificationRepo = ref.read(notificationRepositoryProvider);
      await notificationRepo.notifyAdmins(
        notificationType: NotificationType.materialDelivered,
        title: '📦 Material Delivered',
        message: 'Customer:\n$customerName\n\nDelivery Staff:\n$staffName\n\nMaterial:\n${widget.dispatch['material_name']} × ${widget.dispatch['quantity']}',
        dispatchId: widget.dispatch['id'],
        relatedRecordId: widget.dispatch['customer_id'],
      );

      setState(() {
        _status = 'Delivered';
        _uploadedPhotoUrl = finalPhotoUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery marked as completed successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error completing delivery: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.dispatch['customers'] ?? {};
    final customerName = customer['name'] ?? 'N/A';
    final mobile = customer['mobile'] as String?;
    final appId = customer['pm_surya_ghar_application_id'] ?? 'N/A';
    final address = customer['address'] ?? customer['village'] ?? 'N/A';
    final material = widget.dispatch['material_name'] ?? 'N/A';
    final quantity = widget.dispatch['quantity'] ?? 0;
    
    final bool hasPhoto = _pickedPhoto != null || _uploadedPhotoUrl != null;
    final bool isDelivered = _status == 'Delivered';

    return Scaffold(
      appBar: AppBar(
        title: const Text('DELIVERY DETAILS', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Details Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Customer Name:', customerName, isHeader: true),
                    const Divider(height: 20),
                    if (mobile != null && mobile.trim().isNotEmpty) ...[
                      Row(
                        children: [
                          const Text('Mobile Number: ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                          Expanded(
                            child: SelectableText(
                              mobile,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.call, color: Colors.blue),
                            tooltip: 'Call Customer',
                            onPressed: () async {
                              final Uri url = Uri(scheme: 'tel', path: mobile);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.message, color: Colors.green),
                            tooltip: 'WhatsApp Customer',
                            onPressed: () async {
                              final cleanMobile = mobile.replaceAll(RegExp(r'\D'), '');
                              final Uri url = Uri.parse('https://wa.me/91$cleanMobile');
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildInfoRow('PM Surya Ghar App ID:', appId),
                    _buildInfoRow('Site Address:', address),
                    _buildInfoRow('Material:', material),
                    _buildInfoRow('Quantity:', '$quantity'),
                    _buildInfoRow('Dispatch Status:', _status, statusColor: _statusColor(_status)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Photo Preview
            if (_uploadedPhotoUrl != null) ...[
              const Text('Uploaded Delivery Photo:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _uploadedPhotoUrl!, 
                  height: 200, 
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image, size: 48, color: Colors.green),
                          SizedBox(height: 8),
                          Text('Delivery Photo Uploaded', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ] else if (_pickedPhoto != null) ...[
              const Text('Selected Delivery Photo:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.image, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_pickedPhoto!.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Action Buttons
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_status == 'Pending')
                ElevatedButton(
                  onPressed: _startDelivery,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('START DELIVERY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              if (_status == 'Out for Delivery') ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('TAKE DELIVERY PHOTO'),
                  onPressed: _takePhoto,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: hasPhoto ? _markDelivered : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('MARK DELIVERED', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
              if (isDelivered)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Delivered successfully!',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Delivered':
        return Colors.green;
      case 'Out for Delivery':
        return Colors.orange;
      case 'Pending':
      default:
        return Colors.red;
    }
  }

  Widget _buildInfoRow(String label, String value, {bool isHeader = false, Color? statusColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isHeader ? Colors.black : Colors.grey,
                fontSize: isHeader ? 16 : 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isHeader ? FontWeight.bold : FontWeight.w500,
                fontSize: isHeader ? 16 : 14,
                color: statusColor ?? Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
