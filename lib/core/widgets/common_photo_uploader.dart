import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'photo_upload_source_dialog.dart';

class CommonPhotoUploader extends StatelessWidget {
  final String title;
  final File? selectedFile;
  final String? existingImageUrl;
  final PhotoUploadResult? photoResult;
  final ValueChanged<PhotoUploadResult> onPhotoSelected;
  final VoidCallback? onPhotoRemoved;

  const CommonPhotoUploader({
    super.key,
    this.title = 'Installation Geo-Tagged Photo',
    this.selectedFile,
    this.existingImageUrl,
    this.photoResult,
    required this.onPhotoSelected,
    this.onPhotoRemoved,
  });

  Future<void> _pickPhoto(BuildContext context) async {
    final result = await PhotoUploadSourceDialog.selectAndProcessPhoto(
      context,
      categoryTitle: title,
      requireGeoTag: true,
    );

    if (result != null) {
      onPhotoSelected(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = selectedFile != null;
    final hasUrl = existingImageUrl != null && existingImageUrl!.isNotEmpty;
    final hasPhoto = hasFile || hasUrl;

    final isGeoTagged = photoResult?.hasGps ?? (hasUrl); // URL assumes valid geotagged image

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.camera_enhance_outlined, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                if (hasPhoto)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isGeoTagged ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isGeoTagged ? Colors.green.shade400 : Colors.amber.shade400),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isGeoTagged ? Icons.check_circle : Icons.warning_amber_rounded,
                          size: 14,
                          color: isGeoTagged ? Colors.green : Colors.amber.shade900,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isGeoTagged ? '✓ Geo-tagged' : '⚠ No GPS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isGeoTagged ? Colors.green.shade900 : Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (hasPhoto) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: hasFile
                          ? (kIsWeb
                              ? Image.network(selectedFile!.path, fit: BoxFit.cover)
                              : Image.file(selectedFile!, fit: BoxFit.cover))
                          : Image.network(existingImageUrl!, fit: BoxFit.cover),
                    ),
                  ),
                  if (onPhotoRemoved != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white, size: 18),
                          onPressed: onPhotoRemoved,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickPhoto(context),
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: Text(hasPhoto ? 'CHANGE PHOTO' : 'CAPTURE / UPLOAD PHOTO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
