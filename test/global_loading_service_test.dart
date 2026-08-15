import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_crm/core/services/global_loading_service.dart';
import 'package:solar_crm/core/localization/app_strings.dart';

void main() {
  group('GlobalLoadingService Unit Tests', () {
    late ProviderContainer container;
    late GlobalLoadingNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(globalLoadingProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is idle', () {
      final state = container.read(globalLoadingProvider);
      expect(state.isLoading, false);
      expect(state.activeCount, 0);
      expect(state.hasError, false);
    });

    test('show increments active count and sets message', () {
      notifier.show(type: LoadingType.saveLoading, message: 'Saving customer...');
      var state = container.read(globalLoadingProvider);
      expect(state.isLoading, true);
      expect(state.activeCount, 1);
      expect(state.message, 'Saving customer...');

      notifier.show(type: LoadingType.uploadLoading, message: 'Uploading attachment...');
      state = container.read(globalLoadingProvider);
      expect(state.activeCount, 2);
      expect(state.message, 'Uploading attachment...');
    });

    test('hide decrements active count and resets when 0', () {
      notifier.show(type: LoadingType.saveLoading);
      notifier.show(type: LoadingType.uploadLoading);
      expect(container.read(globalLoadingProvider).activeCount, 2);

      notifier.hide();
      expect(container.read(globalLoadingProvider).activeCount, 1);
      expect(container.read(globalLoadingProvider).isLoading, true);

      notifier.hide();
      expect(container.read(globalLoadingProvider).activeCount, 0);
      expect(container.read(globalLoadingProvider).isLoading, false);
    });

    test('runWithLoading executes action and cleans up count', () async {
      bool actionRan = false;
      final result = await notifier.runWithLoading(
        () async {
          actionRan = true;
          return 'SUCCESS';
        },
        type: LoadingType.dataLoading,
      );

      expect(actionRan, true);
      expect(result, 'SUCCESS');
      expect(container.read(globalLoadingProvider).isLoading, false);
      expect(container.read(globalLoadingProvider).activeCount, 0);
    });

    test('AppStrings localization keys return fallback or English default', () {
      expect(AppStrings.loading, 'Loading...');
      expect(AppStrings.retry, 'RETRY');
      expect(AppStrings.get('unknown_key', fallback: 'Fallback'), 'Fallback');
    });
  });
}
