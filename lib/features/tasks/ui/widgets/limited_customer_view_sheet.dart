import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Role-Specific Limited Customer View Sheet
/// Exposes ONLY basic contact and work details.
/// Financial data, profit, loan details, admin remarks, and internal records are STRICTLY EXCLUDED.
class LimitedCustomerViewSheet extends StatelessWidget {
  final String customerName;
  final String mobile;
  final String address;
  final String? village;
  final String? applicationId;
  final String roleCategory;
  final List<Widget>? roleSpecificInfoWidgets;

  const LimitedCustomerViewSheet({
    super.key,
    required this.customerName,
    required this.mobile,
    required this.address,
    this.village,
    this.applicationId,
    required this.roleCategory,
    this.roleSpecificInfoWidgets,
  });

  static void show({
    required BuildContext context,
    required String customerName,
    required String mobile,
    required String address,
    String? village,
    String? applicationId,
    required String roleCategory,
    List<Widget>? roleSpecificInfoWidgets,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LimitedCustomerViewSheet(
        customerName: customerName,
        mobile: mobile,
        address: address,
        village: village,
        applicationId: applicationId,
        roleCategory: roleCategory,
        roleSpecificInfoWidgets: roleSpecificInfoWidgets,
      ),
    );
  }

  Future<void> _makeCall(BuildContext context) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: mobile);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch phone dialer for $mobile')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error calling customer: $e')),
        );
      }
    }
  }

  Future<void> _openMap(BuildContext context) async {
    final query = Uri.encodeComponent('$address ${village ?? ""}');
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Maps app')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening maps: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person, color: theme.primaryColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customer Info ($roleCategory View)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 24),

          // Contact Details
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phone, color: Colors.green),
            title: Text(mobile, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Customer Mobile'),
            trailing: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.call, size: 16),
              label: const Text('CALL'),
              onPressed: () => _makeCall(context),
            ),
          ),

          const SizedBox(height: 8),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on, color: Colors.redAccent),
            title: Text(address.isNotEmpty ? address : (village ?? 'N/A')),
            subtitle: Text(village != null && village!.isNotEmpty ? 'Village: $village' : 'Delivery/Site Location'),
            trailing: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.map, size: 16),
              label: const Text('MAP'),
              onPressed: () => _openMap(context),
            ),
          ),

          if (applicationId != null && applicationId!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.assignment_ind, color: Colors.orange),
              title: Text(applicationId!, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Application ID / Consumer No.'),
            ),
          ],

          if (roleSpecificInfoWidgets != null && roleSpecificInfoWidgets!.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Work Context Information',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ...roleSpecificInfoWidgets!,
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
