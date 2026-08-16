import 'package:flutter/material.dart';
import 'consolidated_installation_widget.dart';

class CustomerAdminPhotosWidget extends StatelessWidget {
  final String customerId;

  const CustomerAdminPhotosWidget({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    return ConsolidatedInstallationSummaryCard(customer: {'id': customerId});
  }
}
