import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/trip_card.dart' show RouteTimeline, RouteTimelineStop, formatDayLabel, formatFcfa;
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../services/booking_repository.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen>
    with SingleTickerProviderStateMixin, AutoRefresh<MyTripsScreen> {
  @override
  Future<void> onAutoRefresh() => _loadBookings(silent: true);

  late TabController _tabController;
  List<Booking> _bookings = [];
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookings();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (shouldPoll(context)) _loadBookings(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings({bool silent = false}) async {
    final userId = context.read<AppProvider>().user?.id;
    if (!silent) {
      setState(() => _isLoading = true);
    }
    var bookings = <Booking>[];
    try {
      if (userId != null) {
        bookings = await BookingRepository()
            .fetchForPassenger(userId)
            .timeout(const Duration(seconds: 15));
      }
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  List<Booking> get _upcoming => _bookings
      .where((b) =>
          b.status == BookingStatus.confirmed ||
          b.status == BookingStatus.pending)
      .toList();

  List<Booking> get _past => _bookings
      .where((b) =>
          b.status == BookingStatus.completed ||
          b.status == BookingStatus.cancelled ||
          b.status == BookingStatus.refused)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(
        title: 'Mes réservations',
        actions: const [NotificationBellButton(onBrand: true), SizedBox(width: 8)],
        bottomHeight: 46,
        bottom: _TabBar(controller: _tabController),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadBookings,
          child: TabBarView(
            controller: _tabController,
            children: [
              _isLoading
                  ? const _LoadingState()
                  : _hasError
                      ? _ErrorState(onRetry: _loadBookings)
                      : _upcoming.isEmpty
                          ? const _EmptyState(
                              message: 'Aucun trajet à venir',
                              subtitle:
                                  'Recherchez un trajet pour faire votre première réservation.',
                              icon: Icons.directions_bus_outlined,
                            )
                          : _BookingList(bookings: _upcoming),
              _isLoading
                  ? const _LoadingState()
                  : _hasError
                      ? _ErrorState(onRetry: _loadBookings)
                      : _past.isEmpty
                          ? const _EmptyState(
                              message: 'Aucun historique',
                              subtitle: 'Vos trajets passés apparaîtront ici.',
                              icon: Icons.history,
                            )
                          : _BookingList(bookings: _past),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const TravelerBottomNavBar(current: ClientTab.bookings),
    );
  }
}

/// Onglets « À venir / Passés » en segmenté de verre sur l'en-tête.
class _TabBar extends StatelessWidget {
  final TabController controller;

  const _TabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => GlowSegmented<int>(
        onBrand: true,
        value: controller.index,
        options: const [(0, 'À venir'), (1, 'Passés')],
        onChanged: controller.animateTo,
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  final List<Booking> bookings;

  const _BookingList({required this.bookings});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return _BookingCard(
          booking: booking,
          onTap: booking.trip == null
              ? null
              : booking.status == BookingStatus.completed
                  ? () => context.push('/rate/${booking.trip!.id}')
                  : () => context.push('/trip/${booking.trip!.id}/tracking'),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onTap;

  const _BookingCard({required this.booking, required this.onTap});

  StatusChipVariant get _chipVariant {
    switch (booking.status) {
      case BookingStatus.confirmed:
        return StatusChipVariant.confirmed;
      case BookingStatus.pending:
        return StatusChipVariant.pending;
      case BookingStatus.refused:
        return StatusChipVariant.refused;
      // « Manqué » (le chauffeur est reparti sans lui) n'est pas une faute
      // du passager : en gris, pas en rouge.
      case BookingStatus.cancelled:
        return booking.isMissed ? StatusChipVariant.completed : StatusChipVariant.cancelled;
      case BookingStatus.completed:
        return StatusChipVariant.completed;
    }
  }

  /// Ce que le toucher ouvre, dit en clair sur la carte.
  String? get _action {
    switch (booking.status) {
      case BookingStatus.confirmed:
        return 'Voir le billet';
      case BookingStatus.pending:
        return 'Suivre';
      case BookingStatus.completed:
        return 'Noter';
      case BookingStatus.cancelled:
      case BookingStatus.refused:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip;
    if (trip == null) {
      return NeuBox(
        child: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Trajet indisponible', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
    }

    final time = DateFormat('HH:mm');
    final boardAt = booking.boardingStop?.scheduledAt ?? trip.departureTime;
    final arriveAt = booking.alightingStop?.scheduledAt ?? trip.departureTime.add(trip.estimatedDuration);
    // Durée du tronçon du passager, pas du trajet entier du chauffeur.
    final segmentDuration = TripSegment(
      boarding: booking.boardingStop,
      alighting: booking.alightingStop,
      pricePerSeat: 0,
    ).durationLabel(trip);
    final action = onTap == null ? null : _action;

    return NeuBox(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusChip(variant: _chipVariant, customLabel: booking.statusLabel),
              const Spacer(),
              Text(
                formatDayLabel(boardAt),
                style: AppTextStyles.bodySemibold.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RouteTimeline(
            stops: [
              RouteTimelineStop(time: time.format(boardAt), place: booking.boardingStop?.name ?? trip.departure),
              RouteTimelineStop(time: time.format(arriveAt), place: booking.alightingStop?.name ?? trip.arrival),
            ],
            duration: segmentDuration,
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.event_seat_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${booking.seatsBooked} place${booking.seatsBooked > 1 ? 's' : ''}',
                style: AppTextStyles.caption,
              ),
              const SizedBox(width: 12),
              Text(formatFcfa(booking.totalPrice), style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (action != null) ...[
                Text(action, style: AppTextStyles.bodySemibold.copyWith(color: AppColors.brandText, fontWeight: FontWeight.w700)),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.brandText),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final String subtitle;
  final IconData icon;

  const _EmptyState({
    required this.message,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: AppTextStyles.title2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            GlowButton(
              label: 'Rechercher un trajet',
              leadingIcon: Icons.search_rounded,
              expanded: false,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.borderStrong),
            const SizedBox(height: 16),
            Text(
              'Impossible de charger vos réservations',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}
