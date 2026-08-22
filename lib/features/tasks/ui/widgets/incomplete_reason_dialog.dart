import 'package:flutter/material.dart';

class IncompleteReasonDialog extends StatefulWidget {
  const IncompleteReasonDialog({super.key});

  static Future<String?> show(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const IncompleteReasonDialog(),
    );
  }

  @override
  State<IncompleteReasonDialog> createState() => _IncompleteReasonDialogState();
}

class _IncompleteReasonDialogState extends State<IncompleteReasonDialog> {
  final List<String> _reasons = const [
    'Material Not Available',
    'Site Not Ready',
    'Customer Not Available',
    'Technical Problem',
    'Other',
  ];

  String _selectedReason = 'Material Not Available';
  final TextEditingController _customReasonController = TextEditingController();

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('MARK AS NOT COMPLETED', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select reason for incomplete task:', style: TextStyle(fontSize: 13, color: Colors.black87)),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _selectedReason,
            onChanged: (val) {
              if (val != null) setState(() => _selectedReason = val);
            },
            child: Column(
              children: _reasons.map(
                (reason) => RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  value: reason,
                ),
              ).toList(),
            ),
          ),
          if (_selectedReason == 'Other') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customReasonController,
              decoration: const InputDecoration(
                labelText: 'Specify reason...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () {
            final reason = _selectedReason == 'Other'
                ? (_customReasonController.text.trim().isNotEmpty ? _customReasonController.text.trim() : 'Other')
                : _selectedReason;
            Navigator.pop(context, reason);
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}
