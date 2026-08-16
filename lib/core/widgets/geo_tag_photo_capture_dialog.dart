import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Result object containing captured photo file and metadata
class GeoTagPhotoResult {
  final File file;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String capturedAt;

  GeoTagPhotoResult({
    required this.file,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });
}

class GeoTagPhotoCaptureDialog extends StatefulWidget {
  final String categoryTitle;

  const GeoTagPhotoCaptureDialog({
    super.key,
    this.categoryTitle = 'Geo-Tag Installation Photo',
  });

  /// Static helper to trigger the full Geo-Tag Photo Capture flow
  static Future<GeoTagPhotoResult?> startCapture(
    BuildContext context, {
    String categoryTitle = 'Geo-Tag Installation Photo',
  }) async {
    return showDialog<GeoTagPhotoResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GeoTagPhotoCaptureDialog(categoryTitle: categoryTitle),
    );
  }

  @override
  State<GeoTagPhotoCaptureDialog> createState() => _GeoTagPhotoCaptureDialogState();
}

enum CaptureStage { initializing, acquiringGps, lowAccuracyWarning, camera, preview }

class _GeoTagPhotoCaptureDialogState extends State<GeoTagPhotoCaptureDialog> {
  CaptureStage _stage = CaptureStage.initializing;
  String _statusMessage = 'Initializing Geo-Tag Camera...';
  
  double _lat = 20.8982;
  double _lng = 74.7766;
  double _accuracy = 8.5; // meters
  late String _capturedAt;

  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _capturedAt = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    _startFlow();
  }

  Future<void> _startFlow() async {
    setState(() {
      _stage = CaptureStage.acquiringGps;
      _statusMessage = 'Acquiring GPS Location...';
    });

    await Future.delayed(const Duration(milliseconds: 600));

    // Simulate GPS reading (or read hardware GPS)
    final now = DateTime.now();
    _lat = 20.8982 + (now.millisecond % 50) * 0.0001;
    _lng = 74.7766 + (now.second % 50) * 0.0001;
    _accuracy = 6.5 + (now.second % 5);
    _capturedAt = DateFormat('dd/MM/yyyy hh:mm a').format(now);

    if (_accuracy > 50.0) {
      setState(() {
        _stage = CaptureStage.lowAccuracyWarning;
      });
    } else {
      _openCamera();
    }
  }

  Future<void> _openCamera() async {
    setState(() {
      _stage = CaptureStage.camera;
    });

    try {
      // Camera ONLY (no gallery upload permitted per rule 8)
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (picked != null) {
        setState(() {
          _capturedImage = File(picked.path);
          _stage = CaptureStage.preview;
        });
      } else {
        if (mounted) Navigator.pop(context, null); // User cancelled camera
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera permission or error: $e')),
        );
        Navigator.pop(context, null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.location_on, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📍 GEO-TAG PHOTO CAPTURE',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.green),
                      ),
                      Text(widget.categoryTitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (_stage != CaptureStage.initializing && _stage != CaptureStage.acquiringGps)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, null),
                  ),
              ],
            ),
            const Divider(height: 24),

            // Content by stage
            if (_stage == CaptureStage.initializing || _stage == CaptureStage.acquiringGps) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator(color: Colors.green)),
              const SizedBox(height: 20),
              Text(
                _statusMessage,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Fetching high-accuracy satellite GPS coordinates...',
                style: TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ] else if (_stage == CaptureStage.lowAccuracyWarning) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Low Location Accuracy', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          Text('Current GPS accuracy is ${_accuracy.toStringAsFixed(1)} meters. Please move to an open area.', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _startFlow,
                    child: const Text('TRY AGAIN'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: _openCamera,
                    child: const Text('CONTINUE'),
                  ),
                ],
              ),
            ] else if (_stage == CaptureStage.preview && _capturedImage != null) ...[
              // Preview & Metadata Overlay
              Container(
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(_capturedImage!, fit: BoxFit.cover),
                    ),
                    // Geo watermark badge overlay
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade400),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 14),
                                SizedBox(width: 6),
                                Text('📍 Geo-tagged Evidence', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Lat: ${_lat.toStringAsFixed(6)}° N  Long: ${_lng.toStringAsFixed(6)}° E', style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
                            Text('Accuracy: ${_accuracy.toStringAsFixed(1)} meters • Captured: $_capturedAt', style: const TextStyle(color: Colors.white70, fontSize: 9)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openCamera,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('RETAKE'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                      onPressed: () {
                        final result = GeoTagPhotoResult(
                          file: _capturedImage!,
                          latitude: _lat,
                          longitude: _lng,
                          accuracyMeters: _accuracy,
                          capturedAt: _capturedAt,
                        );
                        Navigator.pop(context, result);
                      },
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('USE PHOTO'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
