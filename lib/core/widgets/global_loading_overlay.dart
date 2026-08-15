import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/global_loading_service.dart';
import '../localization/app_strings.dart';

class GlobalLoadingOverlay extends ConsumerWidget {
  const GlobalLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadingState = ref.watch(globalLoadingProvider);

    if (!loadingState.isLoading) {
      return const SizedBox.shrink();
    }

    final message = loadingState.message ?? AppStrings.loading;
    final progress = loadingState.progress;

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withOpacity(0.60),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Branded App Logo or Spinner
                    Image.asset(
                      'assets/icon/app_icon.png',
                      height: 56,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.solar_power,
                        size: 48,
                        color: Color(0xFF1E88E5),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (progress != null) ...[
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade200,
                        color: Theme.of(context).primaryColor,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable inline loading indicator for screen/page data
class GlobalDataLoadingWidget extends StatelessWidget {
  final String? message;

  const GlobalDataLoadingWidget({
    super.key,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
          ),
          const SizedBox(height: 16),
          Text(
            message ?? AppStrings.dataLoading,
            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Reusable inline error and retry widget for screen/page data
class GlobalErrorWidget extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const GlobalErrorWidget({
    super.key,
    this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              message ?? AppStrings.unableToLoad,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppStrings.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
