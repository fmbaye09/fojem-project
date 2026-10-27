import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/price_display.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../models/trip.dart';
import '../../../models/driver.dart';
import '../../../models/booking.dart';
import '../../../providers/app_provider.dart';
import '../../../services/chat_repository.dart';
import '../../../services/trip_repository.dart';
import '../../../services/booking_repository.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Trip? _trip;
  Booking? _existingBooking;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    final trip = await TripRepository().fetch(widget.tripId);
    final userId = context.read<AppProvider>().user?.id;
    Booking? existing;
    if (userId != null) {
      existing = await BookingRepository().fetchActiveForTrip(
        tripId: widget.tripId,
        passengerId: userId,
      );
    }
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _existingBooking = existing;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Détail du trajet'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (_trip?.driver != null)
            IconButton(
              onPressed: () => _messageDriver(context),
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Contacter le chauffeur',
            ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _trip == null
              ? const _TripNotFound()
              : _TripContent(
                  trip: _trip!,
                  existingBooking: _existingBooking,
                  onBook: () => context.push(
                    '/seat-selection?tripId=${_trip!.id}',
                  ),
                ),
    );
  }

  Future<void> _messageDriver(BuildContext context) async {
    final trip = _trip;
    final userId = context.read<AppProvider>().user?.id;
    if (trip?.driver == null || userId == null) return;

    final conversation = await ChatRepository().findOrCreate(
      userIdA: userId,
      userIdB: trip!.driverId,
      relatedTripId: trip.id,
    );
    if (!context.mounted) return;
    context.push('/chat/${conversation.id}?name=${trip.driver!.name}&otherId=${trip.driverId}');
  }
}

class _TripContent extends StatelessWidget {
  final Trip trip;
  final Booking? existingBooking;
  final VoidCallback onBook;

  const _TripContent({
    required this.trip,
    this.existingBooking,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteHeader(trip: trip),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (trip.waypointLocations.isNotEmpty) ...[
                        _RouteTimeline(trip: trip),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      _DriverSection(driver: trip.driver!),
                      const SizedBox(height: AppSpacing.lg),
                      _TripDetailsSection(trip: trip),
                      const SizedBox(height: AppSpacing.lg),
                      _PriceSection(trip: trip),
                      const SizedBox(height: AppSpacing.lg),
                      if (trip.driver!.reviews.isNotEmpty) ...[
                        _ReviewsSection(driver: trip.driver!),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _BookingBar(
          trip: trip,
          existingBooking: existingBooking,
          onBook: onBook,
        ),
      ],
    );
  }
}

/// Timeline verticale départ → étapes → arrivée (design/screens/
/// fojem_trip_detail.png). Les heures des étapes intermédiaires sont
/// interpolées proportionnellement à leur position sur le trajet — aucune
/// donnée d'heure de passage réelle par étape n'existe (pas de segmentation
/// d'itinéraire par étape côté backend), donc c'est indicatif, pas un horaire
/// garanti.
class _RouteTimeline extends StatelessWidget {
  final Trip trip;

  const _RouteTimeline({required this.trip});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final stops = [
      (label: trip.departure, isFirst: true, isLast: false),
      for (final w in trip.waypointLocations) (label: w.address, isFirst: false, isLast: false),
      (label: trip.arrival, isFirst: false, isLast: true),
    ];
    final totalMinutes = trip.estimatedDuration.inMinutes;
    final step = stops.length > 1 ? totalMinutes / (stops.length - 1) : 0;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stops.length; i++)
            _TimelineRow(
              label: stops[i].label,
              time: timeFormat.format(trip.departureTime.add(Duration(minutes: (step * i).round()))),
              isFirst: stops[i].isFirst,
              isLast: stops[i].isLast,
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final String time;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.label,
    required this.time,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                if (!isFirst) Expanded(child: Container(width: 2, color: AppColors.primary)),
                if (isLast)
                  const Icon(Icons.location_on, color: AppColors.primary, size: 20)
                else
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFirst ? AppColors.background : AppColors.primary,
                      border: isFirst ? Border.all(color: AppColors.primary, width: 2) : null,
                    ),
                  ),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.bodyLargeSemibold, overflow: TextOverflow.ellipsis),
                  Text(time, style: AppTextStyles.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteHeader extends StatelessWidget {
  final Trip trip;

  const _RouteHeader({required this.trip});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('EEE d MMM', 'fr_FR');
    final arrival = trip.departureTime.add(trip.estimatedDuration);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeFormat.format(trip.departureTime),
                      style: AppTextStyles.title1.copyWith(fontSize: 28),
                    ),
                    Text(
                      trip.departure,
                      style: AppTextStyles.bodyLargeSemibold,
                    ),
                    Text(
                      trip.departureAddress,
                      style: AppTextStyles.caption,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trip.durationLabel,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeFormat.format(arrival),
                      style: AppTextStyles.title1.copyWith(fontSize: 28),
                    ),
                    Text(
                      trip.arrival,
                      style: AppTextStyles.bodyLargeSemibold,
                      textAlign: TextAlign.end,
                    ),
                    Text(
                      trip.arrivalAddress,
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const StatusChip(variant: StatusChipVariant.confirmed),
              const SizedBox(width: AppSpacing.sm),
              Text(
                dateFormat.format(trip.departureTime),
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(
                    Icons.event_seat_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''} dispo.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverSection extends StatelessWidget {
  final Driver driver;

  const _DriverSection({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Votre chauffeur', style: AppTextStyles.title2),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: AppSpacing.cardPadding,
          decoration: AppColors.cardDecoration,
          child: Column(
            children: [
              Row(
                children: [
                  DriverAvatar(
                    name: driver.name,
                    photoUrl: driver.photoUrl,
                    isOnline: driver.isOnline,
                    size: 56,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driver.name, style: AppTextStyles.bodyLargeSemibold),
                        const SizedBox(height: 4),
                        StarRating(
                          rating: driver.rating,
                          size: 16,
                          reviewCount: driver.totalTrips,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${driver.totalTrips} trajets effectués',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        context.push('/profile/driver/${driver.id}'),
                    icon: const Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(
                    Icons.directions_car_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver.vehicle.model,
                          style: AppTextStyles.bodySemibold,
                        ),
                        Text(
                          '${driver.vehicle.color} · ${driver.vehicle.plateNumber}',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      driver.vehicle.typeLabel,
                      style: AppTextStyles.label.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TripDetailsSection extends StatelessWidget {
  final Trip trip;

  const _TripDetailsSection({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Informations du trajet', style: AppTextStyles.title2),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: AppColors.cardDecoration,
          child: Column(
            children: [
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Point de départ',
                value: trip.departureAddress,
              ),
              const Divider(height: 1, color: AppColors.border, indent: 52),
              _DetailRow(
                icon: Icons.flag_outlined,
                label: 'Point d\'arrivée',
                value: trip.arrivalAddress,
              ),
              const Divider(height: 1, color: AppColors.border, indent: 52),
              _DetailRow(
                icon: Icons.schedule_outlined,
                label: 'Durée estimée',
                value: trip.durationLabel,
              ),
              const Divider(height: 1, color: AppColors.border, indent: 52),
              _DetailRow(
                icon: Icons.event_seat_outlined,
                label: 'Places disponibles',
                value: '${trip.availableSeats} sur ${trip.seatsTotal}',
              ),
              if (trip.notes != null) ...[
                const Divider(height: 1, color: AppColors.border, indent: 52),
                _DetailRow(
                  icon: Icons.info_outline,
                  label: 'Notes du chauffeur',
                  value: trip.notes!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.bodySemibold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceSection extends StatelessWidget {
  final Trip trip;

  const _PriceSection({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tarif', style: AppTextStyles.title2),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: AppSpacing.cardPadding,
          decoration: AppColors.cardDecoration,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Prix par place', style: AppTextStyles.body),
                  PriceDisplay(amount: trip.pricePerSeat),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Aucuns frais cachés',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  final Driver driver;

  const _ReviewsSection({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Avis récents', style: AppTextStyles.title2),
            StarRating(rating: driver.rating, size: 16),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...driver.reviews.map(
          (review) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ReviewCard(review: review),
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('d MMM yyyy', 'fr_FR').format(review.date);

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(review.authorName, style: AppTextStyles.bodySemibold),
              const Spacer(),
              StarRating(
                rating: review.rating,
                size: 13,
                showLabel: false,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(dateStr, style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(review.comment, style: AppTextStyles.body),
        ],
      ),
    );
  }
}

class _BookingBar extends StatelessWidget {
  final Trip trip;
  final Booking? existingBooking;
  final VoidCallback onBook;

  const _BookingBar({
    required this.trip,
    this.existingBooking,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Prix par place', style: AppTextStyles.caption),
                  PriceDisplay(amount: trip.pricePerSeat, isLarge: true),
                  if (!trip.isFull && trip.availableSeats <= 3 && existingBooking == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''} restante${trip.availableSeats > 1 ? 's' : ''}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: existingBooking != null
                    ? FojemButton.secondary(
                        label: existingBooking!.status == BookingStatus.confirmed
                            ? 'Billet & Code QR'
                            : 'Demande en attente',
                        prefixIcon: existingBooking!.status == BookingStatus.confirmed
                            ? Icons.qr_code_2_rounded
                            : Icons.hourglass_top_rounded,
                        onPressed: () => context.push('/trip/${trip.id}/tracking'),
                      )
                    : FojemButton.primary(
                        label: trip.isFull ? 'Complet' : 'Réserver ce trajet',
                        suffixIcon:
                            trip.isFull ? null : Icons.arrow_forward_rounded,
                        onPressed: trip.isFull ? null : onBook,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripNotFound extends StatelessWidget {
  const _TripNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.border,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Trajet introuvable', style: AppTextStyles.title2),
          const SizedBox(height: AppSpacing.xl),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Retour'),
          ),
        ],
      ),
    );
  }
}
