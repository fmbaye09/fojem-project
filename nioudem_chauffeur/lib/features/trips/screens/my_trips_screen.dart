import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/trip_card.dart' show formatDayLabel, formatFcfa;
import '../../../core/widgets/status_chip.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../services/trip_repository.dart';

/// Onglet « Mes trajets » — liste des trajets publiés par le chauffeur,
/// avec design enrichi : cards visuelles avec itinéraire, stats rapides,
/// et filtres À venir / Terminés.
class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

enum _Filter { upcoming, past }

class _MyTripsScreenState extends State<MyTripsScreen> with AutoRefresh<MyTripsScreen> {
  @override
  Future<void> onAutoRefresh() => _load(silent: true);

  bool _isLoading = true;
  bool _hasError = false;
  List<Trip> _trips = [];
  _Filter _filter = _Filter.upcoming;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final driverId = context.read<AppProvider>().user?.id;
    if (driverId == null) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final trips = await TripRepository().fetchForDriver(driverId);
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  List<Trip> get _filtered {
    final now = DateTime.now();
    return _trips.where((t) {
      final isUpcoming = (t.status == TripStatus.upcoming || t.status == TripStatus.inProgress) &&
          t.departureTime.isAfter(now.subtract(const Duration(hours: 6)));
      return _filter == _Filter.upcoming ? isUpcoming : !isUpcoming;
    }).toList()
      ..sort((a, b) => _filter == _Filter.upcoming
          ? a.departureTime.compareTo(b.departureTime)
          : b.departureTime.compareTo(a.departureTime));
  }

  @override
  Widget build(BuildContext context) {
    final upcomingCount = _trips.where((t) {
      final now = DateTime.now();
      return (t.status == TripStatus.upcoming || t.status == TripStatus.inProgress) &&
          t.departureTime.isAfter(now.subtract(const Duration(hours: 6)));
    }).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(
        title: 'Mes trajets',
        subtitle: '${_trips.length} trajet${_trips.length > 1 ? 's' : ''} au total',
        actions: [
          GlassIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Publier un trajet',
            onPressed: () => context.push('/publish-trip'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // ── Filter tabs ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _FilterSwitch(
                filter: _filter,
                upcomingCount: upcomingCount,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),
            const SizedBox(height: 8),

            // ── List ──
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                      )
                    : _hasError
                        ? _Notice('Impossible de charger vos trajets pour le moment.')
                        : _buildList(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const DriverBottomNavBar(current: DriverTab.trips),
    );
  }

  Widget _buildList() {
    final trips = _filtered;
    if (trips.isEmpty) {
      return ListView(
        children: [
          _Empty(isUpcoming: _filter == _Filter.upcoming),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final trip = trips[index];
        return _DriverTripCard(
          trip: trip,
          onTap: () => context.push('/trip/${trip.id}'),
        );
      },
    );
  }
}

class _FilterSwitch extends StatelessWidget {
  final _Filter filter;
  final int upcomingCount;
  final ValueChanged<_Filter> onChanged;

  const _FilterSwitch({
    required this.filter,
    required this.upcomingCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      ),
      child: Row(
        children: [
          Expanded(child: _SegmentButton(
            label: 'À venir',
            badge: upcomingCount > 0 ? upcomingCount : null,
            isActive: filter == _Filter.upcoming,
            onTap: () => onChanged(_Filter.upcoming),
          )),
          Expanded(child: _SegmentButton(
            label: 'Terminés',
            isActive: filter == _Filter.past,
            onTap: () => onChanged(_Filter.past),
          )),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final int? badge;
  final bool isActive;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    this.badge,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
          border: isActive ? Border.all(color: AppColors.primary.withOpacity(0.2)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.bodySemibold.copyWith(
                fontSize: 14,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : AppColors.textMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverTripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;

  const _DriverTripCard({required this.trip, required this.onTap});

  StatusChipVariant get _variant {
    switch (trip.status) {
      case TripStatus.upcoming:
        return StatusChipVariant.confirmed;
      case TripStatus.inProgress:
        return StatusChipVariant.pending;
      case TripStatus.completed:
        return StatusChipVariant.completed;
      case TripStatus.cancelled:
        return StatusChipVariant.cancelled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookedSeats = trip.seatsTotal - trip.availableSeats;
    final fillPercent = trip.seatsTotal > 0 ? bookedSeats / trip.seatsTotal : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
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
                  // Route row with visual dots
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
                      // Dotted line
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
                      // Destination dot
                      const Icon(Icons.location_on_rounded, size: 16, color: AppColors.danger),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // City names
                  Row(
                    children: [
                      Expanded(
                        child: Text(trip.departure,
                            style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 16)),
                      ),
                      Expanded(
                        child: Text(trip.arrival,
                            textAlign: TextAlign.right,
                            style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 16)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Date + Status
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 15, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${formatDayLabel(trip.departureTime)} • '
                          '${trip.departureTime.hour.toString().padLeft(2, '0')}:'
                          '${trip.departureTime.minute.toString().padLeft(2, '0')}',
                          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                      StatusChip(variant: _variant),
                    ],
                  ),
                ],
              ),
            ),
            // Bottom bar with seats + price
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAF8),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppSpacing.borderRadiusCard - 1)),
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  // Seats progress
                  const Icon(Icons.people_alt_outlined, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text('$bookedSeats/${trip.seatsTotal}',
                      style: AppTextStyles.bodySemibold.copyWith(fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fillPercent,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          fillPercent >= 1.0 ? AppColors.danger : AppColors.primary,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(formatFcfa(trip.pricePerSeat),
                      style: AppTextStyles.priceLarge.copyWith(fontSize: 16)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool isUpcoming;

  const _Empty({required this.isUpcoming});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isUpcoming ? Icons.directions_car_outlined : Icons.history_rounded,
              size: 36,
              color: AppColors.primary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isUpcoming ? 'Aucun trajet à venir' : 'Aucun trajet terminé',
            style: AppTextStyles.bodyLargeSemibold,
          ),
          const SizedBox(height: 8),
          Text(
            isUpcoming
                ? 'Publiez un trajet depuis l\'accueil pour\nle voir apparaître ici.'
                : 'Vos trajets terminés apparaîtront ici.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, height: 1.5),
          ),
          if (isUpcoming) ...[
            const SizedBox(height: 24),
            InkWell(
              onTap: () => context.push('/publish-trip'),
              borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                ),
                child: Text(
                  'Publier un trajet',
                  style: AppTextStyles.bodySemibold.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice(this.text);

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
          child: Column(
            children: [
              const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.borderStrong),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
