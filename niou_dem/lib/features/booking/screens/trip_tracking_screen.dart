import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/chat_repository.dart';
import '../../../services/map/osm_map_service.dart';
import '../../../services/trip_repository.dart';

enum _TrackingStep { confirmed, driverConfirmed, departed, arrived }

class TripTrackingScreen extends StatefulWidget {
  final String tripId;

  const TripTrackingScreen({super.key, required this.tripId});

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  Trip? _trip;
  Booking? _booking;
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) _loadSilently();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSilently() async {
    try {
      final userId = mounted ? context.read<AppProvider>().user?.id : null;
      final trip = await TripRepository().fetch(widget.tripId);
      Booking? booking;
      if (userId != null) {
        booking = await BookingRepository().fetchActiveForTrip(
          tripId: widget.tripId,
          passengerId: userId,
        );
      }
      if (!mounted) return;
      setState(() {
        if (trip != null) _trip = trip;
        if (booking != null) _booking = booking;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final userId = mounted ? context.read<AppProvider>().user?.id : null;
    final trip = await TripRepository().fetch(widget.tripId);
    Booking? booking;
    if (userId != null) {
      booking = await BookingRepository().fetchActiveForTrip(
        tripId: widget.tripId,
        passengerId: userId,
      );
      if (booking == null) {
        final all = await BookingRepository().fetchForPassenger(userId);
        for (final b in all) {
          if (b.tripId == widget.tripId) {
            booking = b;
            break;
          }
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _booking = booking;
      _isLoading = false;
    });
  }

  _TrackingStep _stepFor(Trip trip, Booking? booking) {
    if (booking?.status == BookingStatus.completed) return _TrackingStep.arrived;
    if (booking?.isBoarded == true) return _TrackingStep.departed;

    final now = DateTime.now();
    final arrival = trip.departureTime.add(trip.estimatedDuration);
    if (now.isAfter(arrival)) return _TrackingStep.arrived;
    if (now.isAfter(trip.departureTime)) return _TrackingStep.departed;
    if (booking?.status == BookingStatus.confirmed) {
      return _TrackingStep.driverConfirmed;
    }
    return _TrackingStep.confirmed;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_trip == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Suivi du trajet')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppColors.border),
              const SizedBox(height: 12),
              Text('Trajet introuvable', style: AppTextStyles.title2),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Suivi du trajet'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_booking != null) ...[
                _QrTicketCard(booking: _booking!, trip: _trip!),
                const SizedBox(height: AppSpacing.lg),
              ],
              _LiveTrackingMap(trip: _trip!),
              const SizedBox(height: AppSpacing.lg),
              _DriverContactCard(trip: _trip!),
              const SizedBox(height: AppSpacing.lg),
              Text('Statut du trajet', style: AppTextStyles.title2),
              const SizedBox(height: AppSpacing.md),
              _TrackingTimeline(currentStep: _stepFor(_trip!, _booking)),
              const SizedBox(height: AppSpacing.lg),
              _TripInfoCard(trip: _trip!),
              const SizedBox(height: AppSpacing.lg),
              const _SupportSection(),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrTicketCard extends StatelessWidget {
  final Booking booking;
  final Trip trip;

  const _QrTicketCard({required this.booking, required this.trip});

  @override
  Widget build(BuildContext context) {
    final isCompleted = booking.status == BookingStatus.completed;
    final isConfirmed = booking.status == BookingStatus.confirmed;
    final isBoarded = booking.isBoarded;

    final Color primaryColor = isCompleted
        ? const Color(0xFF2E7D32)
        : (isBoarded
            ? const Color(0xFF2E7D32)
            : (isConfirmed ? AppColors.primary : const Color(0xFFF59E0B)));

    final Color bgColor = isCompleted
        ? const Color(0xFFE8F5E9)
        : (isBoarded
            ? const Color(0xFFE8F5E9)
            : (isConfirmed ? AppColors.primarySurface : const Color(0xFFFFFBEB)));

    final String titleText = isCompleted
        ? 'Trajet terminé avec succès'
        : (isBoarded
            ? 'Présence validée à bord'
            : (isConfirmed ? 'Billet & Code QR d\'embarquement' : 'Réservation en attente'));

    final IconData titleIcon = isCompleted
        ? Icons.task_alt_rounded
        : (isBoarded
            ? Icons.check_circle_rounded
            : (isConfirmed ? Icons.qr_code_2_rounded : Icons.hourglass_top_rounded));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // En-tête ticket
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(titleIcon, color: primaryColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titleText,
                    style: AppTextStyles.bodySemibold.copyWith(color: primaryColor),
                  ),
                ),
                StatusChip(
                  variant: (isCompleted || isBoarded)
                      ? StatusChipVariant.completed
                      : (isConfirmed ? StatusChipVariant.confirmed : StatusChipVariant.pending),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (isCompleted) ...[
                  const Icon(Icons.check_circle_outline_rounded, size: 54, color: Color(0xFF2E7D32)),
                  const SizedBox(height: 12),
                  Text('Bon retour !', style: AppTextStyles.title2),
                  const SizedBox(height: 6),
                  Text(
                    'Votre voyage s\'est bien terminé. Nous espérons que vous avez passé un excellent trajet.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ] else if (isConfirmed) ...[
                  // QR Code
                  Container(
                    width: 170,
                    height: 170,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: QrImageView(
                      data: 'FOJEM:${booking.id}:${booking.confirmationCode}',
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Code de confirmation en grand
                  Text(
                    'Code d\'embarquement',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      booking.confirmationCode.isNotEmpty
                          ? booking.confirmationCode
                          : (booking.id.length >= 8 ? booking.id.substring(0, 8).toUpperCase() : booking.id),
                      style: AppTextStyles.display.copyWith(
                        fontSize: 22,
                        letterSpacing: 4,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isBoarded
                        ? 'Votre présence a été validée par le chauffeur.'
                        : 'Présentez ce QR code ou dictez le code au chauffeur avant le départ.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 12.5,
                      color: isBoarded ? const Color(0xFF2E7D32) : AppColors.textSecondary,
                      fontWeight: isBoarded ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.hourglass_top_rounded, size: 40, color: Color(0xFFD97706)),
                  const SizedBox(height: 12),
                  Text(
                    'En attente d\'acceptation',
                    style: AppTextStyles.bodyLargeSemibold,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Le chauffeur a reçu votre demande. Dès qu\'il valide, votre billet et votre code QR d\'embarquement apparaîtront ici.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),

                // Récapitulatif rapide
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _DetailItem(
                      label: 'Places',
                      value: '${booking.seatsBooked} place${booking.seatsBooked > 1 ? 's' : ''}',
                    ),
                    Container(height: 24, width: 1, color: AppColors.border),
                    _DetailItem(
                      label: 'Prix payé',
                      value: '${booking.totalPrice.toInt()} FCFA',
                    ),
                    Container(height: 24, width: 1, color: AppColors.border),
                    _DetailItem(
                      label: 'Départ',
                      value: DateFormat('HH:mm').format(trip.departureTime),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;

  const _DetailItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.bodySemibold.copyWith(fontSize: 13)),
      ],
    );
  }
}

class _DriverContactCard extends StatelessWidget {
  final Trip trip;

  const _DriverContactCard({required this.trip});

  Future<void> _callDriver(BuildContext context) async {
    final phone = trip.driver?.phoneNumber;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro de téléphone indisponible.')),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _messageDriver(BuildContext context) async {
    final userId = context.read<AppProvider>().user?.id;
    if (userId == null) return;

    try {
      final conversation = await ChatRepository().findOrCreate(
        userIdA: userId,
        userIdB: trip.driverId,
        relatedTripId: trip.id,
      );
      if (!context.mounted) return;
      context.push(
        '/chat/${conversation.id}?name=${Uri.encodeComponent(trip.driver?.name ?? 'Chauffeur')}&otherId=${trip.driverId}',
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir la messagerie.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = trip.driver;

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DriverAvatar(
            name: driver?.name ?? 'Chauffeur',
            photoUrl: driver?.photoUrl,
            isOnline: driver?.isOnline ?? true,
            size: 52,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver?.name ?? 'Chauffeur', style: AppTextStyles.bodyLargeSemibold),
                const SizedBox(height: 2),
                Text(
                  driver?.vehicle.model.isNotEmpty == true
                      ? '${driver!.vehicle.brand} ${driver.vehicle.model}'
                      : 'Véhicule vérifié',
                  style: AppTextStyles.caption,
                ),
                if (driver?.vehicle.plateNumber.isNotEmpty == true)
                  Text(
                    driver!.vehicle.plateNumber,
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _messageDriver(context),
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary, size: 20),
            ),
          ),
          IconButton(
            onPressed: () => _callDriver(context),
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phone_outlined, color: Color(0xFF2E7D32), size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingTimeline extends StatelessWidget {
  final _TrackingStep currentStep;

  const _TrackingTimeline({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep(
        step: _TrackingStep.confirmed,
        title: 'Réservation validée',
        subtitle: 'Votre place est confirmée',
        isCompleted: true,
        isCurrent: currentStep == _TrackingStep.confirmed,
      ),
      _TimelineStep(
        step: _TrackingStep.driverConfirmed,
        title: 'Confirmation chauffeur',
        subtitle: 'Le chauffeur prépare le départ',
        isCompleted: currentStep.index >= _TrackingStep.driverConfirmed.index,
        isCurrent: currentStep == _TrackingStep.driverConfirmed,
      ),
      _TimelineStep(
        step: _TrackingStep.departed,
        title: 'En route / À bord',
        subtitle: 'Présence validée, voyage en cours',
        isCompleted: currentStep.index >= _TrackingStep.departed.index,
        isCurrent: currentStep == _TrackingStep.departed,
      ),
      _TimelineStep(
        step: _TrackingStep.arrived,
        title: 'Arrivée à destination',
        subtitle: 'Fin du trajet',
        isCompleted: currentStep.index >= _TrackingStep.arrived.index,
        isCurrent: currentStep == _TrackingStep.arrived,
      ),
    ];

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: steps.asMap().entries.map((entry) {
          final isLast = entry.key == steps.length - 1;
          return _TimelineStepWidget(
            step: entry.value,
            isLast: isLast,
          );
        }).toList(),
      ),
    );
  }
}

class _TimelineStep {
  final _TrackingStep step;
  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isCurrent;

  const _TimelineStep({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.isCompleted,
    required this.isCurrent,
  });
}

class _TimelineStepWidget extends StatelessWidget {
  final _TimelineStep step;
  final bool isLast;

  const _TimelineStepWidget({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step.isCompleted ? AppColors.primary : AppColors.border,
              ),
              child: step.isCompleted
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 38,
                color: step.isCompleted ? AppColors.primary : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: step.isCurrent
                      ? AppTextStyles.bodySemibold
                      : AppTextStyles.body,
                ),
                const SizedBox(height: 2),
                Text(
                  step.subtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TripInfoCard extends StatelessWidget {
  final Trip trip;

  const _TripInfoCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM yyyy à HH:mm', 'fr_FR');

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Détails du trajet', style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Départ',
            value: dateFormat.format(trip.departureTime),
          ),
          const Divider(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.trip_origin,
            label: 'Lieu de départ',
            value: trip.departure,
          ),
          const Divider(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Destination',
            value: trip.arrival,
          ),
          const Divider(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'Tarif',
            value: '${trip.pricePerSeat.toInt()} FCFA / place',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: AppTextStyles.caption),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.bodySemibold.copyWith(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.help_outline, color: AppColors.primary, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Besoin d\'aide ?', style: AppTextStyles.bodyLargeSemibold),
                const SizedBox(height: 2),
                Text(
                  'Notre assistance est disponible 24/7.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => context.push('/support'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Contacter'),
          ),
        ],
      ),
    );
  }
}

class _LiveTrackingMap extends StatefulWidget {
  final Trip trip;

  const _LiveTrackingMap({required this.trip});

  @override
  State<_LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<_LiveTrackingMap> {
  final _controller = MapController();
  late final ll.LatLng _origin;
  late final ll.LatLng _destination;
  late List<ll.LatLng> _path;

  @override
  void initState() {
    super.initState();
    final o = (widget.trip.origin.lat != 0 && widget.trip.origin.lng != 0)
        ? widget.trip.origin
        : coordinatesForCity(widget.trip.departure);
    final d = (widget.trip.destination.lat != 0 && widget.trip.destination.lng != 0)
        ? widget.trip.destination
        : coordinatesForCity(widget.trip.arrival);
    _origin = ll.LatLng(o.lat, o.lng);
    _destination = ll.LatLng(d.lat, d.lng);
    _path = [
      _origin,
      for (final wp in widget.trip.waypointLocations) ll.LatLng(wp.lat, wp.lng),
      _destination,
    ];
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    try {
      final o = (widget.trip.origin.lat != 0 && widget.trip.origin.lng != 0)
          ? widget.trip.origin
          : coordinatesForCity(widget.trip.departure);
      final d = (widget.trip.destination.lat != 0 && widget.trip.destination.lng != 0)
          ? widget.trip.destination
          : coordinatesForCity(widget.trip.arrival);
      final route = await OsmMapService()
          .getRoute(o, d)
          .timeout(const Duration(seconds: 8));
      if (route == null || route.polyline.length < 2 || !mounted) return;
      setState(() =>
          _path = [for (final p in route.polyline) ll.LatLng(p.lat, p.lng)]);
    } catch (_) {}
  }

  CameraFit get _fit => CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          _origin,
          _destination,
          _currentVehiclePosition,
        ]),
        padding: const EdgeInsets.all(40),
      );

  ll.LatLng get _currentVehiclePosition {
    if (widget.trip.status == TripStatus.completed) return _destination;
    final cLat = widget.trip.currentLat;
    final cLng = widget.trip.currentLng;
    if (cLat != null && cLng != null && (cLat != 0 || cLng != 0)) {
      return ll.LatLng(cLat, cLng);
    }
    if (_path.length < 2) return _origin;
    if (widget.trip.status == TripStatus.inProgress) {
      final midIndex = _path.length ~/ 2;
      return _path[midIndex];
    }
    return _origin;
  }

  String? get _lastGpsSignalLabel {
    final updated = widget.trip.locationUpdatedAt;
    if (updated == null) return null;
    final diff = DateTime.now().difference(updated);
    if (diff.inSeconds < 15) return 'Position GPS en direct';
    if (diff.inMinutes < 1) return 'Signal GPS il y a ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'Signal GPS il y a ${diff.inMinutes} min';
    return 'Dernier signal à ${DateFormat('HH:mm').format(updated.toLocal())}';
  }

  Future<void> _openExternalMap() async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=${_origin.latitude},${_origin.longitude}&destination=${_destination.latitude},${_destination.longitude}&travelmode=driving');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isInProgress = widget.trip.status == TripStatus.inProgress;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête de la carte
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.surface,
            child: Row(
              children: [
                Icon(
                  isInProgress ? Icons.sensors_rounded : Icons.map_outlined,
                  size: 20,
                  color: isInProgress ? const Color(0xFF2E7D32) : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isInProgress ? 'Localisation en direct' : 'Itinéraire du trajet',
                        style: AppTextStyles.bodySemibold.copyWith(
                          color: isInProgress ? const Color(0xFF2E7D32) : AppColors.textPrimary,
                        ),
                      ),
                      if (_lastGpsSignalLabel != null)
                        Text(
                          _lastGpsSignalLabel!,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isInProgress)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2E7D32),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'EN ROUTE',
                          style: AppTextStyles.caption.copyWith(
                            color: const Color(0xFF2E7D32),
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCameraFit: _fit,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'sn.fojem.app',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _path,
                          color: AppColors.primary,
                          strokeWidth: 4,
                          strokeCap: StrokeCap.round,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _origin,
                          width: 36,
                          height: 36,
                          child: const Icon(Icons.trip_origin_rounded, color: Color(0xFF2E7D32), size: 28),
                        ),
                        Marker(
                          point: _destination,
                          width: 36,
                          height: 36,
                          child: const Icon(Icons.location_on_rounded, color: AppColors.danger, size: 34),
                        ),
                        Marker(
                          point: _currentVehiclePosition,
                          width: 44,
                          height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.directions_car_filled_rounded,
                              color: AppColors.primary,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Column(
                    children: [
                      Material(
                        color: AppColors.surface,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () => _controller.fitCamera(_fit),
                          borderRadius: BorderRadius.circular(8),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(Icons.my_location_rounded, size: 20, color: AppColors.textPrimary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: AppColors.surface,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: _openExternalMap,
                          borderRadius: BorderRadius.circular(8),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(Icons.open_in_new_rounded, size: 20, color: AppColors.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
