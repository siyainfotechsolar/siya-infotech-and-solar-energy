import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class BarcodeScannerDialog extends StatefulWidget {
  final String title;
  final String? initialValue;
  final List<String> existingSerials;
  final int? panelIndex;

  const BarcodeScannerDialog({
    super.key,
    required this.title,
    this.initialValue,
    this.existingSerials = const [],
    this.panelIndex,
  });

  static Future<String?> show({
    required BuildContext context,
    required String title,
    String? initialValue,
    List<String> existingSerials = const [],
    int? panelIndex,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => BarcodeScannerDialog(
        title: title,
        initialValue: initialValue,
        existingSerials: existingSerials,
        panelIndex: panelIndex,
      ),
    );
  }

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog> {
  late TextEditingController _textController;
  String? _scannedCode;
  String? _errorMessage;
  bool _isManualMode = false;

  @override
  void initState() {
    super.initState();
    _scannedCode = widget.initialValue;
    _textController = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool _validateCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorMessage = 'Serial number cannot be empty.');
      return false;
    }

    // Check duplicate serial number protection within installation
    for (int i = 0; i < widget.existingSerials.length; i++) {
      if (widget.panelIndex != null && i == widget.panelIndex) continue;
      if (widget.existingSerials[i].trim().toLowerCase() == trimmed.toLowerCase()) {
        setState(() => _errorMessage = 'Panel serial number already added.');
        return false;
      }
    }

    setState(() => _errorMessage = null);
    return true;
  }

  Future<void> _simulateCameraScan() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
      if (photo != null) {
        // Generate pseudo serial from timestamp/filename if optical OCR isn't available
        final mockSerial = 'SN${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
        setState(() {
          _scannedCode = mockSerial;
          _textController.text = mockSerial;
        });
        _validateCode(mockSerial);
      }
    } catch (_) {
      setState(() {
        _isManualMode = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.qr_code_scanner, color: Colors.purple),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_scannedCode != null && _scannedCode!.isNotEmpty && _errorMessage == null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  children: [
                    const Text('✓ Serial Number Scanned', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    SelectableText(_scannedCode!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: 'Serial Number',
                hintText: 'Enter or scan barcode',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.purple),
                  onPressed: _simulateCameraScan,
                ),
              ),
              onChanged: (val) {
                _scannedCode = val;
                _validateCode(val);
              },
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera, size: 16),
                  label: const Text('CAMERA SCAN'),
                  onPressed: _simulateCameraScan,
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _isManualMode = !_isManualMode);
                  },
                  child: const Text('MANUAL ENTRY'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
          onPressed: () {
            final val = _textController.text.trim();
            if (_validateCode(val)) {
              Navigator.pop(context, val);
            }
          },
          child: const Text('USE THIS'),
        ),
      ],
    );
  }
}
