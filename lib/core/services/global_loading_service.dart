import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../localization/app_strings.dart';

enum LoadingType {
  initialAppLoading,
  pageLoading,
  dataLoading,
  saveLoading,
  updateLoading,
  uploadLoading,
  importLoading,
  deleteLoading,
  syncLoading,
}

class GlobalLoadingState {
  final int activeCount;
  final LoadingType loadingType;
  final String? message;
  final double? progress;
  final bool hasError;
  final String? errorMessage;

  const GlobalLoadingState({
    this.activeCount = 0,
    this.loadingType = LoadingType.dataLoading,
    this.message,
    this.progress,
    this.hasError = false,
    this.errorMessage,
  });

  bool get isLoading => activeCount > 0;

  GlobalLoadingState copyWith({
    int? activeCount,
    LoadingType? loadingType,
    String? message,
    double? progress,
    bool? hasError,
    String? errorMessage,
  }) {
    return GlobalLoadingState(
      activeCount: activeCount ?? this.activeCount,
      loadingType: loadingType ?? this.loadingType,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class GlobalLoadingNotifier extends Notifier<GlobalLoadingState> {
  @override
  GlobalLoadingState build() => const GlobalLoadingState();

  void show({
    LoadingType type = LoadingType.dataLoading,
    String? message,
    double? progress,
  }) {
    final defaultMsg = _getDefaultMessage(type);
    state = state.copyWith(
      activeCount: state.activeCount + 1,
      loadingType: type,
      message: message ?? defaultMsg,
      progress: progress,
      hasError: false,
      errorMessage: null,
    );
  }

  void showWithMessage(String message, {LoadingType type = LoadingType.dataLoading}) {
    show(type: type, message: message);
  }

  void updateProgress(double progress, {String? message}) {
    if (state.activeCount > 0) {
      state = state.copyWith(
        progress: progress.clamp(0.0, 1.0),
        message: message ?? state.message,
      );
    }
  }

  void hide() {
    final newCount = (state.activeCount - 1).clamp(0, 9999);
    if (newCount == 0) {
      state = const GlobalLoadingState();
    } else {
      state = state.copyWith(activeCount: newCount);
    }
  }

  void reset() {
    state = const GlobalLoadingState();
  }

  void setError(String errorMessage) {
    state = state.copyWith(
      hasError: true,
      errorMessage: errorMessage,
    );
  }

  /// Runs an async action wrapped automatically with Global Loading, timeout, and error handling.
  Future<T?> runWithLoading<T>(
    Future<T> Function() action, {
    LoadingType type = LoadingType.dataLoading,
    String? message,
    Duration timeout = const Duration(seconds: 25),
    String? errorMessage,
  }) async {
    show(type: type, message: message);
    try {
      final result = await action().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(AppStrings.networkTimeout);
        },
      );
      return result;
    } catch (e) {
      debugPrint('GlobalLoadingService operation error: $e');
      rethrow;
    } finally {
      hide();
    }
  }

  String _getDefaultMessage(LoadingType type) {
    switch (type) {
      case LoadingType.initialAppLoading:
        return AppStrings.initialAppLoading;
      case LoadingType.pageLoading:
        return AppStrings.pageLoading;
      case LoadingType.dataLoading:
        return AppStrings.dataLoading;
      case LoadingType.saveLoading:
        return AppStrings.saveLoading;
      case LoadingType.updateLoading:
        return AppStrings.updateLoading;
      case LoadingType.uploadLoading:
        return AppStrings.uploadLoading;
      case LoadingType.importLoading:
        return AppStrings.importLoading;
      case LoadingType.deleteLoading:
        return AppStrings.deleteLoading;
      case LoadingType.syncLoading:
        return AppStrings.syncLoading;
    }
  }
}

final globalLoadingProvider =
    NotifierProvider<GlobalLoadingNotifier, GlobalLoadingState>(
  GlobalLoadingNotifier.new,
);
