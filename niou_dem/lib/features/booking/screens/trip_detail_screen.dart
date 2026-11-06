import 'package:flutter/material.dart';
import '../../../core/events/data_refresh.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/price_display.dart';
import '../../../core/widgets/trip_card.dart' show formatFcfa;
import '../../../core/geo/geo_location.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/location_picker_screen.dart';
import '../../../core/widgets/meeting_point_card.dart';
import '../../../models/proposed_stop.dart';
import '../../../models/trip.dart';
import '../../../models/trip_stop.dart';
import '../../../models/driver.dart';
import '../../../models/booking.dart';
import '../../../providers/app_provider.dart';
import '../../../services/chat_repository.dart';
import '../../../services/trip_repository.dart';
import '../../../services/booking_repository.dart';
import '../widgets/propose_stop_card.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;

  /// Arrêts proposés par la recherche ; sinon le trajet complet.
  final String? boardingStopId;
  final String? alightingStopId;

  const TripDetailScreen({
    super.key,
    required this.tripId,
    this.boardingStopId,
    this.alightingStopId,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> with AutoRefresh<TripDetailScreen> {
  @override
  Future<void> onAutoRefresh() => _loadTrip();

  Trip? _trip;
  Booking? _existingBooking;
  bool _isLoading = true;
  late String? _boardId = widget.boardingStopId;
  late String? _alightId = widget.alightingStopId;

  /// Point proposé par le passager à la place de sa montée ou de sa descente.
  ProposedStop? _proposal;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  TripSegment get _segment =>
      _trip!.segment(boardingStopId: _boardId, alightingStopId: _alightId, proposal: _proposal);

  /// Un point se propose avant le départ, sur un trajet qui a encore des places.
  bool get _canPropose {
    final trip = _trip;
    return trip != null &&
        trip.status == TripStatus.upcoming &&
        !trip.isFull &&
        trip.stops.length >= 2 &&
        trip.match?.enRoute != true &&
        _existingBooking == null;
  }

  /// Monter ou descendre ailleurs : le passager choisit le point, le backend
  /// dit ce qu'il coûte au chauffeur, puis le passager le retient ou non.
  Future<void> _proposeStop() async {
    final boarding = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Proposer un point de rendez-vous', style: AppTextStyles.bodyLargeSemibold),
              subtitle: const Text('Sur la route du chauffeur, loin de ses arrêts.'),
            ),
            const Divider(height: 1, color: AppColors.border),
            ListTile(
              leading: const Icon(Icons.login_rounded, color: AppColors.primary),
              title: const Text('Je monte ailleurs'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.primary),
              title: const Text('Je descends ailleurs'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (boarding == null || !mounted) return;

    final point = await Navigator.push<GeoLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(title: boarding ? 'Où voulez-vous monter ?' : 'Où voulez-vous descendre ?'),
      ),
    );
    if (point == null || !mounted) return;

    final trip = _trip!;
    final ProposedStop proposal;
    try {
      proposal = await BookingRepository().previewProposal(tripId: trip.id, point: point, boarding: boarding);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is ApiException && e.message.isNotEmpty ? e.message : 'Impossible d’évaluer ce point. Réessayez.'),
      ));
      return;
    }
    if (!mounted) return;
    final price = trip
        .segment(boardingStopId: _boardId, alightingStopId: _alightId, proposal: proposal)
        .pricePerSeat;
    if (await confirmProposal(context, proposal, segmentPrice: price) && mounted) {
      setState(() => _proposal = proposal);
    }
  }

  /// Le passager change d'arrêt de montée ou de descente : la montée doit
  /// rester avant la descente.
  Future<void> _chooseStop(TripStop stop) async {
    final seg = _segment;
    final canBoard = seg.alighting == null || stop.position < seg.alighting!.position;
    final canAlight = seg.boarding == null || stop.position > seg.boarding!.position;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(stop.name, style: AppTextStyles.bodyLargeSemibold),
              subtitle: Text(stop.displayAddress),
            ),
            const Divider(height: 1, color: AppColors.border),
            ListTile(
              enabled: canBoard,
              leading: const Icon(Icons.login_rounded, color: AppColors.primary),
              title: const Text('Monter ici'),
              onTap: () => Navigator.pop(ctx, 'board'),
            ),
            ListTile(
              enabled: canAlight,
              leading: const Icon(Icons.logout_rounded, color: AppColors.primary),
              title: const Text('Descendre ici'),
              onTap: () => Navigator.pop(ctx, 'alight'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (choice == 'board') {
        _boardId = stop.id;
        _alightId ??= seg.alightingStopId;
        if (_proposal?.isBoarding == true) _proposal = null;
      } else {
        _alightId = stop.id;
        _boardId ??= seg.boardingStopId;
        if (_proposal?.isBoarding == false) _proposal = null;
      }
    });
  }

  void _book() {
    final seg = _segment;
    final params = [
      'tripId=${_trip!.id}',
      if (seg.query.isNotEmpty) seg.query,
      if (_proposal != null) 'proposal=${_proposal!.toQuery()}',
    ].join('&');
    context.push('/seat-selection?$params');
  }

  Future<void> _loadTrip() async {
    final userId = context.read<AppProvider>().user?.id;
    final trip = await TripRepository().fetch(widget.tripId);
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _trip == null
              ? const _TripNotFound()
              : _TripContent(
                  trip: _trip!,
                  segment: _segment,
                  onStopTap: _chooseStop,
                  proposeStop: _canPropose || _proposal != null
                      ? ProposeStopCard(
                          proposal: _proposal,
                          onPropose: _proposeStop,
                          onClear: () => setState(() => _proposal = null),
                        )
                      : null,
                  onMessageDriver: _trip!.driver != null ? () => _messageDriver(context) : null,
                ),
      bottomNavigationBar: _trip == null
          ? null
          : _BookingBar(
              trip: _trip!,
              segment: _segment,
              existingBooking: _existingBooking,
              onBook: _book,
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
  final TripSegment segment;
  final ValueChanged<TripStop> onStopTap;
  final VoidCallback? onMessageDriver;

  /// Proposer un autre point de rendez-vous (avant le départ seulement).
  final Widget? proposeStop;

  const _TripContent({
    required this.trip,
    required this.segment,
    required this.onStopTap,
    required this.onMessageDriver,
    this.proposeStop,
  });

  @override
  Widget build(BuildContext context) {
    final boardAt = segment.boarding?.scheduledAt ?? trip.departureTime;
    return BrandHeaderLayout(
      header: BrandHeader(
        title: 'Détail du trajet',
        subtitle: DateFormat('EEEE d MMMM', 'fr_FR').format(boardAt),
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
        trailing: onMessageDriver == null
            ? null
            : GlassIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                onPressed: onMessageDriver!,
                tooltip: 'Contacter le chauffeur',
              ),
      ),
      children: [
        RiseIn(child: _RouteHeader(trip: trip, segment: segment)),
        const SizedBox(height: AppSpacing.md),
        if (segment.boarding != null) ...[
          RiseIn(
            delay: const Duration(milliseconds: 80),
            child: MeetingPointCard(stop: segment.boarding!),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (trip.stops.length >= 2) ...[
          _StopsTimeline(trip: trip, segment: segment, onStopTap: onStopTap),
          const SizedBox(height: AppSpacing.md),
          if (proposeStop != null) ...[
            proposeStop!,
            const SizedBox(height: AppSpacing.md),
          ],
        ] else if (trip.waypointLocations.isNotEmpty) ...[
          _RouteTimeline(trip: trip),
          const SizedBox(height: AppSpacing.md),
        ],
        if (trip.driver != null) ...[
          _DriverSection(driver: trip.driver!),
          const SizedBox(height: AppSpacing.lg),
        ],
        _TripDetailsSection(trip: trip, segment: segment),
        const SizedBox(height: AppSpacing.lg),
        _PriceSection(segment: segment),
        if (trip.driver?.reviews.isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.lg),
          _ReviewsSection(driver: trip.driver!),
        ],
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

/// Les points de rendez-vous du trajet avec leurs heures publiées. Le
/// tronçon du passager est mis en avant ; toucher un arrêt permet d'y
/// monter ou d'y descendre.
class _StopsTimeline extends StatelessWidget {
  final Trip trip;
  final TripSegment segment;
  final ValueChanged<TripStop> onStopTap;

  const _StopsTimeline({required this.trip, required this.segment, required this.onStopTap});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    // Rang le long du trajet : un point proposé se range juste après
    // l'arrêt qu'il suit, entre deux arrêts du chauffeur.
    final boarding = segment.boarding;
    final alighting = segment.alighting;
    double rank(TripStop stop) {
      if (stop.id != ProposedStop.stopId) return stop.position.toDouble();
      return stop == boarding ? stop.position + 0.5 : stop.position - 0.5;
    }

    final boardRank = boarding == null ? 0.0 : rank(boarding);
    final alightRank = alighting == null ? trip.stops.last.position.toDouble() : rank(alighting);
    final proposed = boarding?.id == ProposedStop.stopId
        ? boarding
        : (alighting?.id == ProposedStop.stopId ? alighting : null);
    final rows = [
      for (final stop in trip.stops) (stop: stop, rank: stop.position.toDouble()),
      if (proposed != null) (stop: proposed, rank: rank(proposed)),
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: AppColors.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Arrêts du trajet', style: AppTextStyles.title2),
          const SizedBox(height: 2),
          Text(
            'Touchez un arrêt pour y monter ou y descendre.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < rows.length; i++)
            InkWell(
              onTap: rows[i].stop == proposed ? null : () => onStopTap(rows[i].stop),
              child: Opacity(
                // Hors de son tronçon : visible mais estompé.
                opacity: rows[i].rank >= boardRank && rows[i].rank <= alightRank ? 1 : 0.45,
                child: _TimelineRow(
                  label: rows[i].stop.name,
                  time: [
                    if (rows[i].stop.scheduledAt != null) timeFormat.format(rows[i].stop.scheduledAt!),
                    if (rows[i].rank == boardRank) 'Vous montez',
                    if (rows[i].rank == alightRank) 'Vous descendez',
                    if (rows[i].stop == proposed) 'point proposé, à confirmer par le chauffeur',
                    if (rows[i].stop.displayAddress != rows[i].stop.name) rows[i].stop.displayAddress,
                  ].join(' · '),
                  isFirst: i == 0,
                  isLast: i == rows.length - 1,
                ),
              ),
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
  final TripSegment segment;

  const _RouteHeader({required this.trip, required this.segment});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('EEE d MMM', 'fr_FR');
    // Le tronçon du passager, pas le trajet complet du chauffeur.
    final departureTime = segment.boarding?.scheduledAt ?? trip.departureTime;
    final arrival = segment.alighting?.scheduledAt ?? trip.departureTime.add(trip.estimatedDuration);
    final departureName = segment.boarding?.name ?? trip.departure;
    final departureAddress = segment.boarding?.displayAddress ?? trip.departureAddress;
    final arrivalName = segment.alighting?.name ?? trip.arrival;
    final arrivalAddress = segment.alighting?.displayAddress ?? trip.arrivalAddress;
    final duration = arrival.difference(departureTime);
    final durationLabel = duration.inMinutes <= 0
        ? trip.durationLabel
        : duration.inHours == 0
            ? '${duration.inMinutes}min'
            : '${duration.inHours}h${(duration.inMinutes % 60).toString().padLeft(2, '0')}';

    // Carte d'itinéraire en verre (template) : montée et descente reliées
    // par une ligne en dégradé, heures en pastille.
    Widget point({
      required String name,
      required String detail,
      required String time,
      required Color color,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 4),
              boxShadow: const [BoxShadow(color: Color(0x2207232F), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.title2),
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlowPill(label: time),
        ],
      );
    }

    return GlassPanel(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VOTRE TRAJET', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary, letterSpacing: 1.6)),
          const SizedBox(height: 16),
          Stack(
            children: [
              Positioned(
                left: 7,
                top: 14,
                bottom: 14,
                child: Container(
                  width: 2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  point(
                    name: departureName,
                    detail: 'Point de rendez-vous · $departureAddress',
                    time: timeFormat.format(departureTime),
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 22),
                  point(
                    name: arrivalName,
                    detail: 'Lieu de dépose · $arrivalAddress',
                    time: timeFormat.format(arrival),
                    color: AppColors.accent,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(dateFormat.format(departureTime), style: AppTextStyles.caption),
              const SizedBox(width: 12),
              const Icon(Icons.timelapse_rounded, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(durationLabel, style: AppTextStyles.caption),
              const Spacer(),
              GlowPill(
                icon: Icons.groups_rounded,
                label: '${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''}',
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
  final TripSegment segment;

  const _TripDetailsSection({required this.trip, required this.segment});

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
                label: 'Vous montez à',
                value: segment.boarding?.displayAddress ?? trip.departureAddress,
              ),
              const Divider(height: 1, color: AppColors.border, indent: 52),
              _DetailRow(
                icon: Icons.flag_outlined,
                label: 'Vous descendez à',
                value: segment.alighting?.displayAddress ?? trip.arrivalAddress,
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
  final TripSegment segment;

  const _PriceSection({required this.segment});

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
                  Expanded(
                    child: Text(
                      segment.boarding != null && segment.alighting != null
                          ? 'Prix par place · ${segment.boarding!.name} → ${segment.alighting!.name}'
                          : 'Prix par place',
                      style: AppTextStyles.body,
                    ),
                  ),
                  PriceDisplay(amount: segment.pricePerSeat),
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
  final TripSegment segment;
  final Booking? existingBooking;
  final VoidCallback onBook;

  const _BookingBar({
    required this.trip,
    required this.segment,
    this.existingBooking,
    required this.onBook,
  });

  /// Barre fixe du bas : prix du tronçon et réservation.
  @override
  Widget build(BuildContext context) {
    return BottomActionBar(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      !trip.isFull && trip.availableSeats <= 3 && existingBooking == null
                          ? 'Plus que ${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''}'
                          : 'Prix par place',
                      style: AppTextStyles.caption.copyWith(
                        color: trip.availableSeats <= 3 ? AppColors.accent : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(formatFcfa(segment.pricePerSeat),
                        style: AppTextStyles.priceLarge.copyWith(fontSize: 21)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (existingBooking != null)
                NeuButton(
                  label: existingBooking!.status == BookingStatus.confirmed ? 'Mon billet' : 'En attente',
                  icon: existingBooking!.status == BookingStatus.confirmed
                      ? Icons.qr_code_2_rounded
                      : Icons.hourglass_top_rounded,
                  onPressed: () => context.push('/trip/${trip.id}/tracking'),
                )
              else
                GlowButton(
                  label: trip.isFull ? 'Complet' : 'Réserver',
                  icon: trip.isFull ? null : Icons.arrow_forward_rounded,
                  expanded: false,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                  onPressed: trip.isFull ? null : onBook,
                ),
            ],
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
