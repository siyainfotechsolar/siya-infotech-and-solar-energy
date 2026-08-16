import 'package:flutter/material.dart';
import '../services/app_navigation_service.dart';

/// Intercepts Android physical back button, swipe gesture, and AppBar back button
/// on forms with unsaved changes.
class UnsavedChangesScope extends StatelessWidget {
  final bool isDirty;
  final Widget child;

  const UnsavedChangesScope({
    super.key,
    required this.isDirty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await AppNavigationService.confirmDiscardChanges(context);
        if (shouldDiscard && context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: child,
    );
  }
}
