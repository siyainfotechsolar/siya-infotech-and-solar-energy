import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../utils/exif_helper.dart';
import 'geo_tag_photo_capture_dialog.dart';

class PhotoUploadResult {
  final File file;
  final String source; // 'APP_CAMERA' or 'GALLERY'
  final String gpsSource; // 'CURRENT_DEVICE_GPS', 'PHOTO_EXIF', or 'NONE'
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? capturedAt;
  final bool hasGps;

  PhotoUploadResult({
    required this.file,
    required this.source,
    required this.gpsSource,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.capturedAt,
  }) : hasGps = latitude != null && longitude != null;
}

class PhotoUploadSourceDialog extends StatefulWidget {
  final String categoryTitle;
  final bool requireGeoTag;

  const PhotoUploadSourceDialog({
    super.key,
    required this.categoryTitle,
    this.requireGeoTag = false,
  });

  /// Static helper method to prompt photo source selection and handle EXIF/GPS logic
  static Future<PhotoUploadResult?> selectAndProcessPhoto(
    BuildContext context, {
    required String categoryTitle,
    bool requireGeoTag = false,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14.0),
              child: Text(
                'ADD INSTALLATION PHOTO',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5, color: Colors.blueGrey),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt, color: Colors.green),
              ),
              title: const Text('📷 CAPTURE PHOTO (Camera + GPS)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Capture photo & current device GPS location', style: TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(ctx, 'CAMERA'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.photo_library, color: Colors.blue),
              ),
              title: const Text('🖼️ UPLOAD EXISTING PHOTO', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Select from phone gallery & read EXIF GPS metadata', style: TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(ctx, 'GALLERY'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (choice == null) return null;

    if (choice == 'CAMERA') {
      if (requireGeoTag) {
        // Strict Geo-Tag Camera capture + Device GPS
        final geoResult = await GeoTagPhotoCaptureDialog.startCapture(
          context,
          categoryTitle: categoryTitle,
        );

        if (geoResult == null) return null;

        return PhotoUploadResult(
          file: geoResult.file,
          source: 'APP_CAMERA',
          gpsSource: 'CURRENT_DEVICE_GPS',
          latitude: geoResult.latitude,
          longitude: geoResult.longitude,
          accuracyMeters: geoResult.accuracyMeters,
          capturedAt: geoResult.capturedAt,
        );
      } else {
        // Standard Camera capture for normal photos (GPS NOT required)
        final XFile? picked = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (picked == null) return null;
        final file = File(picked.path);
        final bytes = await file.readAsBytes();
        final exif = ExifHelper.extractExif(Uint8List.fromList(bytes));

        return PhotoUploadResult(
          file: file,
          source: 'APP_CAMERA',
          gpsSource: exif.hasGps ? 'PHOTO_EXIF' : 'NONE',
          latitude: exif.latitude,
          longitude: exif.longitude,
          capturedAt: exif.dateTimeOriginal ?? DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now()),
        );
      }
    } else {
      // 2. Existing Photo Upload from Gallery
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (picked == null) return null;

      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      final exif = ExifHelper.extractExif(Uint8List.fromList(bytes));

      if (requireGeoTag) {
        // Require EXIF GPS validation modal for Geo-Tag Photo category
        if (context.mounted) {
          return showDialog<PhotoUploadResult>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _ExifValidationModal(
              file: file,
              exif: exif,
              categoryTitle: categoryTitle,
              requireGeoTag: true,
            ),
          );
        }
      } else {
        // Normal photo: Upload directly without requiring GPS!
        return PhotoUploadResult(
          file: file,
          source: 'GALLERY',
          gpsSource: exif.hasGps ? 'PHOTO_EXIF' : 'NONE',
          latitude: exif.latitude,
          longitude: exif.longitude,
          capturedAt: exif.dateTimeOriginal ?? DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now()),
        );
      }
    }

    return null;
  }

  @override
  State<PhotoUploadSourceDialog> createState() => _PhotoUploadSourceDialogState();
}

class _PhotoUploadSourceDialogState extends State<PhotoUploadSourceDialog> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _ExifValidationModal extends StatefulWidget {
  final File file;
  final ExifMetadata exif;
  final String categoryTitle;
  final bool requireGeoTag;

  const _ExifValidationModal({
    required this.file,
    required this.exif,
    required this.categoryTitle,
    required this.requireGeoTag,
  });

  @override
  State<_ExifValidationModal> createState() => _ExifValidationModalState();
}

class _ExifValidationModalState extends State<_ExifValidationModal> {
  @override
  Widget build(BuildContext context) {
    final hasExifGps = widget.exif.hasGps;
    final lat = widget.exif.latitude;
    final lng = widget.exif.longitude;
    final dateStr = widget.exif.dateTimeOriginal ?? DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            hasExifGps ? Icons.check_circle : Icons.warning_amber_rounded,
            color: hasExifGps ? Colors.green : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(
            hasExifGps ? 'GPS FOUND IN PHOTO' : 'NO GPS IN PHOTO',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: hasExifGps ? Colors.green : Colors.orange.shade900,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                widget.file,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),

            if (hasExifGps) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade300)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text('✓ Verified EXIF GPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Latitude: ${lat!.toStringAsFixed(6)}° N', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    Text('Longitude: ${lng!.toStringAsFixed(6)}° E', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    Text('Photo Source: EXISTING PHOTO (GALLERY)', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    Text('GPS Source: PHOTO EXIF', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    Text('Original Date: $dateStr', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, size: 14, color: Colors.orange.shade900),
                        const SizedBox(width: 4),
                        Text('⚠ No GPS Metadata Found', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This photo does not contain EXIF GPS coordinates. The system will NOT falsely mark it as geo-tagged.',
                      style: TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text('Original Date: $dateStr', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('CANCEL'),
        ),

        if (!hasExifGps) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('CAPTURE GEO-TAGGED'),
            onPressed: () async {
              Navigator.pop(context, null);
              final geoResult = await GeoTagPhotoCaptureDialog.startCapture(
                context,
                categoryTitle: widget.categoryTitle,
              );
              if (geoResult != null && context.mounted) {
                Navigator.pop(
                  context,
                  PhotoUploadResult(
                    file: geoResult.file,
                    source: 'APP_CAMERA',
                    gpsSource: 'CURRENT_DEVICE_GPS',
                    latitude: geoResult.latitude,
                    longitude: geoResult.longitude,
                    accuracyMeters: geoResult.accuracyMeters,
                    capturedAt: geoResult.capturedAt,
                  ),
                );
              }
            },
          ),
          if (!widget.requireGeoTag)
            OutlinedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  PhotoUploadResult(
                    file: widget.file,
                    source: 'GALLERY',
                    gpsSource: 'NONE',
                    latitude: null,
                    longitude: null,
                    capturedAt: dateStr,
                  ),
                );
              },
              child: const Text('UPLOAD WITHOUT GPS'),
            ),
        ] else ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(
                context,
                PhotoUploadResult(
                  file: widget.file,
                  source: 'GALLERY',
                  gpsSource: 'PHOTO_EXIF',
                  latitude: lat,
                  longitude: lng,
                  capturedAt: dateStr,
                ),
              );
            },
            child: const Text('USE PHOTO'),
          ),
        ],
      ],
    );
  }
}
