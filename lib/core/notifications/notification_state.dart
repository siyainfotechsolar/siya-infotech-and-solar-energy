import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'notification_model.dart';
import 'notification_repository.dart';

// ─── Repository Provider ──────────────────────────────────────────────────
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return NotificationRepository(supabase);
});

// ─── State ────────────────────────────────────────────────────────────────
class NotificationState {
  final List<AppNotification> notifications;
  final int unreadCount;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;

  const NotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
  });

  NotificationState copyWith({
    List<AppNotification>? notifications,
    int? unreadCount,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────
class NotificationNotifier extends Notifier<NotificationState> {
  RealtimeChannel? _realtimeChannel;
  SupabaseClient? _supabase;
  String? _currentUserId;

  @override
  NotificationState build() {
    ref.onDispose(() {
      _unsubscribeRealtime();
    });
    return const NotificationState();
  }

  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  // Initialize and load first page
  Future<void> initialize(SupabaseClient supabase, String userId) async {
    _supabase = supabase;
    _currentUserId = userId;
    state = const NotificationState(isLoading: true);
    await _loadPage(0);
    _subscribeRealtime(userId);
  }

  Future<void> _loadPage(int page) async {
    final results = await _repo.getNotifications(page: page);
    final count = await _repo.getUnreadCount();
    
    if (page == 0) {
      state = state.copyWith(
        notifications: results,
        unreadCount: count,
        isLoading: false,
        hasMore: results.length == 20,
        currentPage: 0,
      );
    } else {
      final combined = [...state.notifications, ...results];
      state = state.copyWith(
        notifications: combined,
        unreadCount: count,
        isLoading: false,
        hasMore: results.length == 20,
        currentPage: page,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    await _loadPage(state.currentPage + 1);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _loadPage(0);
  }

  // ─── Realtime subscription for new notifications ─────────────────────────
  void _subscribeRealtime(String userId) {
    _unsubscribeRealtime();

    _realtimeChannel = _supabase!
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint('[NotificationState] New notification received via realtime');
            try {
              final newNotif = AppNotification.fromJson(
                payload.newRecord as Map<String, dynamic>,
              );
              state = state.copyWith(
                notifications: [newNotif, ...state.notifications],
                unreadCount: state.unreadCount + 1,
              );
            } catch (e) {
              debugPrint('[NotificationState] Realtime parse error: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: userId,
          ),
          callback: (payload) {
            _refreshUnreadCount();
          },
        )
        .subscribe();

    debugPrint('[NotificationState] Subscribed to realtime notifications for user: $userId');
  }

  void _unsubscribeRealtime() {
    if (_realtimeChannel != null && _supabase != null) {
      _supabase!.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
      debugPrint('[NotificationState] Unsubscribed from notification realtime');
    }
  }

  Future<void> _refreshUnreadCount() async {
    final count = await _repo.getUnreadCount();
    state = state.copyWith(unreadCount: count);
  }

  // ─── Mark as read ─────────────────────────────────────────────────────────
  Future<void> markAsRead(String id) async {
    await _repo.markAsRead(id);
    final updated = state.notifications.map((n) {
      if (n.id == id && !n.isRead) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();
    final newUnread = updated.where((n) => !n.isRead).length;
    state = state.copyWith(notifications: updated, unreadCount: newUnread);
  }

  // ─── Mark all as read ─────────────────────────────────────────────────────
  Future<void> markAllAsRead() async {
    if (_currentUserId == null) return;
    await _repo.markAllAsRead(_currentUserId!);
    final updated = state.notifications.map((n) => n.copyWith(isRead: true)).toList();
    state = state.copyWith(notifications: updated, unreadCount: 0);
  }

  // ─── Cleanup on logout ────────────────────────────────────────────────────
  void clear() {
    _unsubscribeRealtime();
    _currentUserId = null;
    state = const NotificationState();
    debugPrint('[NotificationState] Cleared notification state on logout');
  }
}

// ─── Providers ────────────────────────────────────────────────────────────
final notificationNotifierProvider =
    NotifierProvider<NotificationNotifier, NotificationState>(NotificationNotifier.new);

final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationNotifierProvider).unreadCount;
});
