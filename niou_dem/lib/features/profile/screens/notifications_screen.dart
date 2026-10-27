import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/app_notification.dart';
import '../../../services/notification_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with AutoRefresh<NotificationsScreen> {
  @override
  Future<void> onAutoRefresh() => _loadNotifications(silent: true);

  final _repository = NotificationRepository();
  List<AppNotification>? _notifications;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final list = await _repository.fetchNotifications();
      if (mounted) {
        setState(() {
          _notifications = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger vos notifications.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    final list = _notifications;
    if (list == null || list.isEmpty) return;

    final updated = list.map((n) => n.copyWith(readAt: DateTime.now())).toList();
    setState(() => _notifications = updated);

    await _repository.markAllAsRead();
  }

  Future<void> _onNotificationTap(AppNotification notif) async {
    if (!notif.isRead) {
      final index = _notifications?.indexWhere((n) => n.id == notif.id) ?? -1;
      if (index != -1 && _notifications != null) {
        setState(() {
          _notifications![index] = notif.copyWith(readAt: DateTime.now());
        });
      }
      _repository.markAsRead(notif.id);
    }

    // Navigation contextuelle
    final type = notif.type;
    final payload = notif.payload;
    final tripId = (payload['trip_id'] ?? '').toString();

    if (type == 'chat_message' && payload['conversation_id'] != null) {
      final senderName = payload['sender_name']?.toString() ?? 'Utilisateur';
      final senderId = payload['sender_id']?.toString();
      final convId = payload['conversation_id'].toString();
      context.push('/chat/$convId?name=${Uri.encodeComponent(senderName)}&otherId=${senderId ?? ''}');
    } else if (type == 'booking_completed' && tripId.isNotEmpty) {
      context.push('/rate/$tripId');
    } else if (type == 'booking_confirmed') {
      context.go('/my-trips');
    } else if (tripId.isNotEmpty) {
      context.push('/trip/$tripId');
    } else if (type.startsWith('booking_')) {
      context.go('/my-trips');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications?.any((n) => !n.isRead) ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(
        title: 'Notifications',
        onBack: () => context.pop(),
        actions: [
          if (hasUnread) BrandAppBarTextAction(label: 'Tout lire', onPressed: _markAllRead),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTextStyles.body, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loadNotifications,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final notifications = _notifications ?? [];

    if (notifications.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadNotifications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _EmptyState(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadNotifications,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final notif = notifications[index];
          return _NotificationCard(
            notification: notif,
            onTap: () => _onNotificationTap(notif),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  IconData get _icon {
    switch (notification.type) {
      case 'booking_new':
        return Icons.person_add_alt_1_rounded;
      case 'booking_confirmed':
        return Icons.check_circle_outline_rounded;
      case 'booking_rejected':
      case 'booking_cancelled':
        return Icons.cancel_outlined;
      case 'booking_completed':
        return Icons.flag_outlined;
      case 'chat_message':
        return Icons.chat_bubble_outline_rounded;
      case 'document_status':
        return Icons.verified_user_outlined;
      case 'trip_reminder':
        return Icons.directions_bus_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color get _iconBg {
    switch (notification.type) {
      case 'booking_confirmed':
      case 'booking_completed':
        return const Color(0xFFE8F5E9);
      case 'booking_rejected':
      case 'booking_cancelled':
        return const Color(0xFFFFEBEE);
      case 'chat_message':
        return const Color(0xFFE3F2FD);
      case 'booking_new':
        return AppColors.primarySurface;
      default:
        return AppColors.background;
    }
  }

  Color get _iconColor {
    switch (notification.type) {
      case 'booking_confirmed':
      case 'booking_completed':
        return const Color(0xFF2E7D32);
      case 'booking_rejected':
      case 'booking_cancelled':
        return AppColors.danger;
      case 'chat_message':
        return const Color(0xFF1976D2);
      case 'booking_new':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = notification.isRead;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: isRead ? AppColors.surface : AppColors.primarySurface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          border: Border.all(
            color: isRead
                ? AppColors.border
                : AppColors.primary.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, size: 22, color: _iconColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: AppTextStyles.bodyLargeSemibold.copyWith(
                            fontSize: 15,
                            fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notification.timeAgo,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textMuted,
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F3F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Aucune notification',
            style: AppTextStyles.title2,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Vos réservations, messages et alertes\napparaîtront ici en temps réel.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
