import 'package:flutter/material.dart';

/// Centralized Navigation Service for Siya Solar CRM.
/// Enforces consistent back navigation, duplicate route prevention,
/// unsaved form protection, and deep-link fallbacks.
class AppNavigationService {
  AppNavigationService._();

  /// Centralized push method with duplicate route prevention
  static Future<T?> goTo<T>(
    BuildContext context,
    Widget page, {
    String? routeName,
  }) async {
    final name = routeName ?? page.runtimeType.toString();

    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null && currentRoute.settings.name == name) {
      debugPrint('[AppNavigationService] Blocked duplicate push of route: $name');
      return null;
    }

    return await Navigator.of(context).push<T>(
      MaterialPageRoute(
        settings: RouteSettings(name: name),
        builder: (_) => page,
      ),
    );
  }

  /// Centralized goBack method
  static void goBack<T>(BuildContext context, [T? result]) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop<T>(result);
    } else {
      debugPrint('[AppNavigationService] At root screen, cannot goBack');
    }
  }

  /// Centralized replace method
  static Future<T?> replace<T>(
    BuildContext context,
    Widget page, {
    String? routeName,
  }) async {
    final name = routeName ?? page.runtimeType.toString();
    return await Navigator.of(context).pushReplacement<T, dynamic>(
      MaterialPageRoute(
        settings: RouteSettings(name: name),
        builder: (_) => page,
      ),
    );
  }

  /// Clear navigator history and navigate to root page
  static void clearAndGo(BuildContext context, Widget page) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  /// Unsaved form changes confirmation dialog
  static Future<bool> confirmDiscardChanges(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text('Discard Changes?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard them and go back?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('DISCARD', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
