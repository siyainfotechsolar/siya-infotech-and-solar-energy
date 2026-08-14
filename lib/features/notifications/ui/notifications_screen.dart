import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/notifications/notification_model.dart';
import '../../../core/notifications/notification_state.dart';
import '../../../core/notifications/notification_router.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(notificationNotifierProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'NOTIFICATIONS',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        centerTitle: true,
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () async {
                await ref
                    .read(notificationNotifierProvider.notifier)
                    .markAllAsRead();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All notifications marked as read.')),
                  );
                }
              },
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 13),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(notificationNotifierProvider.notifier).refresh(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'ALL'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('UNREAD'),
                  if (state.unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${state.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NotificationList(
            notifications: state.notifications,
            isLoading: state.isLoading,
            hasMore: state.hasMore,
            scrollController: _scrollController,
            onTap: _onNotificationTap,
            emptyMessage: 'No notifications yet.',
          ),
          _NotificationList(
            notifications: state.notifications.where((n) => !n.isRead).toList(),
            isLoading: state.isLoading,
            hasMore: false,
            scrollController: ScrollController(),
            onTap: _onNotificationTap,
            emptyMessage: 'You\'re all caught up! No unread notifications.',
          ),
        ],
      ),
    );
  }

  Future<void> _onNotificationTap(AppNotification notification) async {
    // Mark as read first
    if (!notification.isRead) {
      await ref
          .read(notificationNotifierProvider.notifier)
          .markAsRead(notification.id);
    }

    if (!mounted) return;
    // Navigate to related record
    await NotificationRouter.handleTap(
      context: context,
      notification: notification,
    );
  }
}

// ─── Notification List Widget ─────────────────────────────────────────────
class _NotificationList extends StatelessWidget {
  final List<AppNotification> notifications;
  final bool isLoading;
  final bool hasMore;
  final ScrollController scrollController;
  final Future<void> Function(AppNotification) onTap;
  final String emptyMessage;

  const _NotificationList({
    required this.notifications,
    required this.isLoading,
    required this.hasMore,
    required this.scrollController,
    required this.onTap,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading && notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: notifications.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          if (index >= notifications.length) {
            return isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          return _NotificationTile(
            notification: notifications[index],
            onTap: () => onTap(notifications[index]),
          );
        },
      ),
    );
  }
}

// ─── Notification Tile ────────────────────────────────────────────────────
class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon ──
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _iconColor(notification.notificationType).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconData(notification.notificationType),
                color: _iconColor(notification.notificationType),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            // ── Content ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(notification.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconData(String type) {
    switch (type) {
      case NotificationType.taskAssigned:
      case NotificationType.taskUpdated:
      case NotificationType.taskReassigned:
        return Icons.assignment;
      case NotificationType.taskCompleted:
        return Icons.task_alt;
      case NotificationType.taskNotCompleted:
        return Icons.warning_amber;
      case NotificationType.deliveryAssigned:
      case NotificationType.deliveryStarted:
      case NotificationType.materialDelivered:
      case NotificationType.materialDispatched:
        return Icons.local_shipping;
      case NotificationType.customerCreated:
      case NotificationType.customerUpdated:
      case NotificationType.customerStageChanged:
        return Icons.person;
      case NotificationType.installationUpdated:
      case NotificationType.installationCompleted:
        return Icons.solar_power;
      case NotificationType.paymentAdded:
      case NotificationType.paymentUpdated:
        return Icons.payments;
      case NotificationType.testNotification:
        return Icons.science;
      default:
        return Icons.notifications;
    }
  }

  Color _iconColor(String type) {
    switch (type) {
      case NotificationType.taskNotCompleted:
        return Colors.orange;
      case NotificationType.taskCompleted:
      case NotificationType.materialDelivered:
      case NotificationType.installationCompleted:
        return Colors.green;
      case NotificationType.taskAssigned:
      case NotificationType.deliveryAssigned:
        return Colors.blue;
      case NotificationType.paymentAdded:
        return Colors.teal;
      case NotificationType.testNotification:
        return Colors.purple;
      default:
        return Colors.blueGrey;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM y').format(dt);
  }
}
