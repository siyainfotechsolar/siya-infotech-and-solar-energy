import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  
  String? _scannedCode;
  String? _errorMessage;
  bool _isManualMode = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _scannedCode = widget.initialValue;
    _textController = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    _scannerController.dispose();
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

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final code = barcodes.first.rawValue!;
      
      // Prevent rapid re-scans of the same or invalid codes
      if (_scannedCode == code) return;
      
      setState(() {
        _scannedCode = code;
        _textController.text = code;
        _isManualMode = true; // Switch to manual mode so they can review the scanned text
      });
      _validateCode(code);
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

            if (!_isManualMode) ...[
              // Camera view
              Container(
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _onDetect,
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: IconButton(
                        icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                        style: IconButton.styleFrom(backgroundColor: Colors.black54),
                        onPressed: () {
                          _scannerController.toggleTorch();
                          setState(() {
                            _isTorchOn = !_isTorchOn;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Point camera at the barcode/QR code to scan', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else ...[
              // Text Field
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'Serial Number',
                  hintText: 'Enter serial number',
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage,
                ),
                onChanged: (val) {
                  _scannedCode = val;
                  _validateCode(val);
                },
              ),
            ],
            
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_isManualMode)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.camera, size: 16),
                    label: const Text('SCAN'),
                    onPressed: () {
                      setState(() {
                        _isManualMode = false;
                        _scannedCode = null;
                        _textController.clear();
                      });
                    },
                  )
                else
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isManualMode = true;
                      });
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
