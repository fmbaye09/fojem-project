import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/price_display.dart';
import '../../../models/booking.dart';
import '../../../providers/app_provider.dart';
import '../../../services/booking_repository.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen>
    with SingleTickerProviderStateMixin {
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
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadBookings(silent: true));
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
      appBar: AppBar(
        title: const Text('Mes réservations'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile/settings'),
          icon: const Icon(Icons.arrow_back),
        ),
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
    );
  }
}

class _TabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;

  const _TabBar({required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: controller,
        labelStyle: AppTextStyles.bodySemibold,
        unselectedLabelStyle: AppTextStyles.body,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: const [
          Tab(text: 'À venir'),
          Tab(text: 'Passés'),
        ],
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
      case BookingStatus.cancelled:
        return StatusChipVariant.cancelled;
      case BookingStatus.completed:
        return StatusChipVariant.completed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('EEE d MMM', 'fr_FR');
    final trip = booking.trip;

    if (trip == null) {
      return Container(
        decoration: AppColors.cardDecoration,
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.help_outline_rounded, color: AppColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Trajet indisponible',
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status + code
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StatusChip(variant: _chipVariant),
                      if (booking.status == BookingStatus.confirmed &&
                          booking.confirmationCode.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            booking.confirmationCode,
                            style: AppTextStyles.label.copyWith(
                              color: AppColors.textMuted,
                              letterSpacing: 1.2,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Visual route
                  Row(
                    children: [
                      // Origin dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 4),
                          ],
                        ),
                      ),
                      // Line
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withOpacity(0.2),
                                AppColors.danger.withOpacity(0.3),
                                AppColors.danger,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      // Destination pin
                      const Icon(Icons.location_on_rounded, size: 16, color: AppColors.danger),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Cities
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          booking.boardingStop?.name ?? trip.departure,
                          style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 15),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          booking.alightingStop?.name ?? trip.arrival,
                          textAlign: TextAlign.right,
                          style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Time info
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFFE67E22)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${timeFormat.format(booking.boardingStop?.scheduledAt ?? trip.departureTime)} → '
                              '${timeFormat.format(booking.alightingStop?.scheduledAt ?? trip.departureTime.add(trip.estimatedDuration))}',
                              style: AppTextStyles.bodySemibold.copyWith(fontSize: 14),
                            ),
                            Text(
                              dateFormat.format(booking.boardingStop?.scheduledAt ?? trip.departureTime),
                              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (trip.durationLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(trip.durationLabel,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Bottom bar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAF8),
                borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(AppSpacing.borderRadiusCard - 1)),
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.airline_seat_recline_normal_rounded,
                      size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Text(
                    '${booking.seatsBooked} place${booking.seatsBooked > 1 ? 's' : ''}',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  PriceDisplay(
                    amount: booking.totalPrice,
                    customStyle: AppTextStyles.priceLarge.copyWith(fontSize: 16),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textMuted,
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
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 40, color: AppColors.primary.withOpacity(0.5)),
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
            InkWell(
              onTap: () => context.go('/home'),
              borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                ),
                child: Text(
                  'Rechercher un trajet',
                  style: AppTextStyles.bodySemibold.copyWith(color: Colors.white),
                ),
              ),
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
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              label: Text(
                'Réessayer',
                style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary),
              ),
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
