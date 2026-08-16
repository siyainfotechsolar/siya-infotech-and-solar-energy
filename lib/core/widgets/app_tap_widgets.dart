import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/connectivity_service.dart';
import '../services/permission_service.dart';

// ─── Double Tap Protection Helper ─────────────────────────────────────────
class Debouncer {
  final int milliseconds;
  int _lastTapTime = 0;

  Debouncer({this.milliseconds = 600});

  bool canExecute() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTapTime < milliseconds) {
      return false;
    }
    _lastTapTime = now;
    return true;
  }
}

// ─── App Feedback SnackBar Utility ─────────────────────────────────────────
class AppFeedback {
  AppFeedback._();

  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void showError(BuildContext context, String message, {VoidCallback? onRetry}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        action: onRetry != null
            ? SnackBarAction(
                label: 'RETRY',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static void showWarning(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ─── Standard Confirmation Dialog ──────────────────────────────────────────
class AppConfirmDialog {
  AppConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'CONFIRM',
    String cancelLabel = 'CANCEL',
    Color confirmColor = Colors.red,
    IconData icon = Icons.warning_amber_rounded,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: confirmColor, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ─── Reusable Button with Double-Tap Protection & Loading Feedback ─────────
class AppButton extends ConsumerStatefulWidget {
  final String label;
  final Future<void> Function()? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final bool requireNetwork;
  final String? requiredModule;
  final String? requiredAction;
  final IconData? icon;
  final Color? color;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.requireNetwork = false,
    this.requiredModule,
    this.requiredAction,
    this.icon,
    this.color,
  });

  @override
  ConsumerState<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends ConsumerState<AppButton> {
  bool _isProcessing = false;
  final _debouncer = Debouncer();

  Future<void> _handleTap() async {
    if (widget.onPressed == null || widget.isLoading || _isProcessing) return;

    if (!_debouncer.canExecute()) {
      debugPrint('[AppButton] Ignored rapid double tap.');
      return;
    }

    // 1. Offline Check
    if (widget.requireNetwork) {
      final isConnected = await AppConnectivity.isConnected();
      if (!isConnected) {
        if (mounted) AppFeedback.showWarning(context, 'No internet connection.');
        return;
      }
    }

    // 2. Permission Check
    if (widget.requiredModule != null) {
      try {
        final perms = await ref.read(currentUserPermissionsProvider.future);
        final action = widget.requiredAction ?? PermissionAction.view;
        if (!perms.can(widget.requiredModule!, action)) {
          if (mounted) {
            AppFeedback.showError(context, "You don't have permission to perform this action.");
          }
          return;
        }
      } catch (_) {}
    }

    // 3. Execute with Double-Tap Protection
    setState(() => _isProcessing = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) AppFeedback.showError(context, 'Operation failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = widget.isLoading || _isProcessing;

    final btnColor = widget.color ?? theme.colorScheme.primary;

    if (widget.isSecondary) {
      return OutlinedButton(
        onPressed: isBusy ? null : _handleTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: btnColor),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: isBusy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: btnColor),
                    const SizedBox(width: 8),
                  ],
                  Text(widget.label, style: TextStyle(color: btnColor, fontWeight: FontWeight.bold)),
                ],
              ),
      );
    }

    return ElevatedButton(
      onPressed: isBusy ? null : _handleTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
      ),
      child: isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                ),
              ],
            ),
    );
  }
}

// ─── Reusable Icon Button with Touch Target (48dp minimum) ────────────────
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final debouncer = Debouncer();

    return IconButton(
      icon: Icon(icon, size: size, color: color),
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: onPressed == null
          ? null
          : () {
              if (debouncer.canExecute()) {
                onPressed!();
              }
            },
    );
  }
}

// ─── Reusable Card with Tap Feedback & Elevation ──────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double elevation;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16.0),
    this.color,
    this.elevation = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    final debouncer = Debouncer();

    return Card(
      elevation: elevation,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                if (debouncer.canExecute()) {
                  onTap!();
                }
              },
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

// ─── Reusable ListTile with Ripple & Touch Height ─────────────────────────
class AppListTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  const AppListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final debouncer = Debouncer();

    return ListTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 12,
      onTap: onTap == null
          ? null
          : () {
              if (debouncer.canExecute()) {
                onTap!();
              }
            },
    );
  }
}
