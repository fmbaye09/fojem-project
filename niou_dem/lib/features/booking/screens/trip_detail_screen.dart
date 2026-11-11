import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/events/data_refresh.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/driver_avatar.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/location_picker_screen.dart';
import '../../../core/widgets/meeting_point_card.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../core/widgets/trip_card.dart' show RouteTimeline, RouteTimelineStop, formatFcfa;
import '../../../models/booking.dart';
import '../../../models/driver.dart';
import '../../../models/proposed_stop.dart';
import '../../../models/trip.dart';
import '../../../models/trip_stop.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/chat_repository.dart';
import '../../../services/trip_repository.dart';
import '../widgets/propose_stop_card.dart';

/// Détail d'un trajet, pour décider en un coup d'œil : l'itinéraire du
/// passager, le chauffeur et son véhicule, les arrêts (touchables pour
/// changer de montée ou de descente), le point de rendez-vous, puis
/// « Réserver » qui ouvre le récapitulatif.
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

  TripSegment get _segment => _trip!.segment(boardingStopId: _boardId, alightingStopId: _alightId, proposal: _proposal);

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
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Proposer un point de rendez-vous', style: AppTextStyles.title2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Sur la route du chauffeur, loin de ses arrêts.', style: AppTextStyles.caption),
            ),
            ListTile(
              leading: const Icon(Icons.login_rounded),
              title: const Text('Je monte ailleurs'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Je descends ailleurs'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
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
    final price = trip.segment(boardingStopId: _boardId, alightingStopId: _alightId, proposal: proposal).pricePerSeat;
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
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: Text(stop.name, style: AppTextStyles.title2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(stop.displayAddress, style: AppTextStyles.caption),
            ),
            ListTile(
              enabled: canBoard,
              leading: const Icon(Icons.login_rounded),
              title: const Text('Monter ici'),
              onTap: () => Navigator.pop(ctx, 'board'),
            ),
            ListTile(
              enabled: canAlight,
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Descendre ici'),
              onTap: () => Navigator.pop(ctx, 'alight'),
            ),
            const SizedBox(height: 8),
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

  /// Récapitulatif direct : le nombre de places s'y choisit, le plan des
  /// sièges y est facultatif.
  void _book() {
    final seg = _segment;
    final count = context.read<SearchProvider>().passengers.clamp(1, _trip!.availableSeats);
    final params = [
      'tripId=${_trip!.id}',
      'count=$count',
      if (seg.query.isNotEmpty) seg.query,
      if (_proposal != null) 'proposal=${_proposal!.toQuery()}',
    ].join('&');
    context.push('/booking/confirm?$params');
  }

  Future<void> _loadTrip() async {
    final userId = context.read<AppProvider>().user?.id;
    final trip = await TripRepository().fetch(widget.tripId);
    Booking? existing;
    if (userId != null) {
      existing = await BookingRepository().fetchActiveForTrip(tripId: widget.tripId, passengerId: userId);
    }
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _existingBooking = existing;
      _isLoading = false;
    });
  }

  Future<void> _messageDriver() async {
    final trip = _trip;
    final userId = context.read<AppProvider>().user?.id;
    if (trip?.driver == null || userId == null) return;
    final conversation = await ChatRepository().findOrCreate(
      userIdA: userId,
      userIdB: trip!.driverId,
      relatedTripId: trip.id,
    );
    if (!mounted) return;
    context.push('/chat/${conversation.id}?name=${trip.driver!.name}&otherId=${trip.driverId}');
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : trip == null
              ? const _TripNotFound()
              : _TripContent(
                  trip: trip,
                  segment: _segment,
                  onStopTap: _chooseStop,
                  proposeStop: _canPropose || _proposal != null
                      ? ProposeStopCard(
                          proposal: _proposal,
                          onPropose: _proposeStop,
                          onClear: () => setState(() => _proposal = null),
                        )
                      : null,
                  onMessageDriver: trip.driver != null ? _messageDriver : null,
                ),
      bottomNavigationBar: trip == null
          ? null
          : _BookingBar(trip: trip, segment: _segment, existingBooking: _existingBooking, onBook: _book),
    );
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
    final arriveAt = segment.alighting?.scheduledAt ?? trip.departureTime.add(trip.estimatedDuration);
    final time = DateFormat('HH:mm');
    return BrandHeaderLayout(
      header: BrandHeader(
        title: toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', 'fr_FR').format(boardAt)) ?? '',
        subtitle: '${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''} libre${trip.availableSeats > 1 ? 's' : ''}',
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        NeuBox(
          child: RouteTimeline(
            stops: [
              RouteTimelineStop(
                time: time.format(boardAt),
                place: segment.boarding?.name ?? trip.departure,
                hint: segment.boarding?.displayAddress ?? trip.departureAddress,
              ),
              RouteTimelineStop(
                time: time.format(arriveAt),
                place: segment.alighting?.name ?? trip.arrival,
                hint: segment.alighting?.displayAddress ?? trip.arrivalAddress,
              ),
            ],
            duration: segment.durationLabel(trip),
          ),
        ),
        if (trip.match?.enRoute == true) ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.alt_route_rounded,
            color: AppColors.success,
            surface: AppColors.successSurface,
            text: 'Trajet déjà en route : votre place est confirmée dès la réservation.',
          ),
        ],
        if (trip.driver != null) ...[
          const SizedBox(height: 12),
          _DriverCard(driver: trip.driver!, onMessage: onMessageDriver),
        ],
        if (segment.boarding != null) ...[
          const SizedBox(height: 12),
          MeetingPointCard(stop: segment.boarding!),
        ],
        if (trip.stops.length >= 2) ...[
          const SizedBox(height: 12),
          _StopsTimeline(trip: trip, segment: segment, onStopTap: onStopTap),
          if (proposeStop != null) ...[
            const SizedBox(height: 12),
            proposeStop!,
          ],
        ],
        const SizedBox(height: 20),
        Text('Bon à savoir', style: AppTextStyles.title2),
        const SizedBox(height: 8),
        NeuBox(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const _InfoTile(
                icon: Icons.payments_outlined,
                title: 'Paiement en espèces au chauffeur',
                subtitle: 'À la montée. Aucun frais caché.',
              ),
              if (trip.notes != null && trip.notes!.trim().isNotEmpty) ...[
                const Divider(indent: 56),
                _InfoTile(icon: Icons.sticky_note_2_outlined, title: 'Mot du chauffeur', subtitle: trip.notes!),
              ],
              const Divider(indent: 56),
              const _InfoTile(
                icon: Icons.verified_user_outlined,
                title: 'Chauffeur vérifié par FOJËM',
                subtitle: 'Pièce d’identité, permis et véhicule contrôlés.',
              ),
            ],
          ),
        ),
        if (trip.driver?.reviews.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _ReviewsSection(driver: trip.driver!),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color surface;
  final String text;

  const _Banner({required this.icon, required this.color, required this.surface, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.bodySemibold.copyWith(color: color))),
        ],
      ),
    );
  }
}

/// Chauffeur et véhicule ; touchable pour son profil, bouton message.
class _DriverCard extends StatelessWidget {
  final Driver driver;
  final VoidCallback? onMessage;

  const _DriverCard({required this.driver, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    final vehicle = driver.vehicle;
    final details = [
      [vehicle.brand, vehicle.model].where((p) => p.trim().isNotEmpty).join(' '),
      vehicle.color,
      vehicle.plateNumber,
    ].where((p) => p.trim().isNotEmpty).join(' · ');
    return NeuBox(
      onTap: () => context.push('/profile/driver/${driver.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          DriverAvatar(name: driver.name, photoUrl: driver.photoUrl, isOnline: driver.isOnline, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyLargeSemibold),
                const SizedBox(height: 2),
                if (driver.rating > 0)
                  StarRating(rating: driver.rating, size: 14, reviewCount: driver.ratingCount > 0 ? driver.ratingCount : null)
                else
                  Text('Nouveau sur FOJËM', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.directions_car_outlined, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onMessage != null)
            IconButton(
              tooltip: 'Écrire au chauffeur',
              onPressed: onMessage,
              style: IconButton.styleFrom(backgroundColor: AppColors.muted),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
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
    final proposed = boarding?.id == ProposedStop.stopId ? boarding : (alighting?.id == ProposedStop.stopId ? alighting : null);
    final rows = [
      for (final stop in trip.stops) (stop: stop, rank: stop.position.toDouble()),
      if (proposed != null) (stop: proposed, rank: rank(proposed)),
    ]..sort((a, b) => a.rank.compareTo(b.rank));

    return NeuBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Arrêts du trajet', style: AppTextStyles.bodyLargeSemibold),
          Text('Touchez un arrêt pour y monter ou y descendre.', style: AppTextStyles.caption),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++)
            () {
              final row = rows[i];
              final inSegment = row.rank >= boardRank && row.rank <= alightRank;
              final role = row.rank == boardRank
                  ? 'Vous montez'
                  : row.rank == alightRank
                      ? 'Vous descendez'
                      : null;
              return InkWell(
                onTap: row.stop == proposed ? null : () => onStopTap(row.stop),
                borderRadius: BorderRadius.circular(10),
                child: _TimelineRow(
                  label: row.stop.name,
                  time: row.stop.scheduledAt != null ? timeFormat.format(row.stop.scheduledAt!) : '',
                  detail: [
                    if (row.stop == proposed) 'Point proposé, à confirmer par le chauffeur',
                    if (row.stop.displayAddress != row.stop.name) row.stop.displayAddress,
                  ].join(' · '),
                  role: role,
                  active: inSegment,
                  isFirst: i == 0,
                  isLast: i == rows.length - 1,
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final String time;
  final String detail;
  final String? role;
  final bool active;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.label,
    required this.time,
    required this.detail,
    required this.role,
    required this.active,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.ink : AppColors.borderStrong;
    final textColor = active ? AppColors.textPrimary : AppColors.textMuted;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(time, style: AppTextStyles.bodySemibold.copyWith(color: textColor, fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(
            width: 20,
            child: Column(
              children: [
                if (!isFirst) Container(width: 2, height: 6, color: color) else const SizedBox(height: 6),
                Container(
                  width: role != null ? 14 : 10,
                  height: role != null ? 14 : 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: role != null ? AppColors.brand : (active ? AppColors.ink : AppColors.surface),
                    border: Border.all(color: role != null ? AppColors.brand : color, width: 2),
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 6 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLargeSemibold.copyWith(color: textColor),
                        ),
                      ),
                      if (role != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.brandSurface, borderRadius: BorderRadius.circular(999)),
                          child: Text(role!, style: AppTextStyles.caption.copyWith(color: AppColors.brandText, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                  if (detail.isNotEmpty)
                    Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: active ? AppColors.textSecondary : AppColors.textMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.textPrimary),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodySemibold),
                Text(subtitle, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
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
        const SizedBox(height: 8),
        for (final review in driver.reviews) ...[
          NeuBox(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(review.authorName, style: AppTextStyles.bodySemibold)),
                    StarRating(rating: review.rating, size: 13, showLabel: false),
                    const SizedBox(width: 6),
                    Text(DateFormat('d MMM yyyy', 'fr_FR').format(review.date), style: AppTextStyles.caption),
                  ],
                ),
                if (review.comment.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(review.comment, style: AppTextStyles.body),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Barre fixe du bas : prix du tronçon et réservation (ou le billet déjà
/// réservé).
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

  @override
  Widget build(BuildContext context) {
    final fewLeft = !trip.isFull && trip.availableSeats <= 2 && existingBooking == null;
    return BottomActionBar(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fewLeft
                      ? 'Plus que ${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''}'
                      : 'Prix par place',
                  style: AppTextStyles.caption.copyWith(
                    color: fewLeft ? AppColors.brandText : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatFcfa(segment.pricePerSeat), maxLines: 1, style: AppTextStyles.priceLarge.copyWith(fontSize: 21)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (existingBooking != null)
            GlowButton(
              label: existingBooking!.status == BookingStatus.confirmed ? 'Mon billet' : 'Ma demande',
              leadingIcon: existingBooking!.status == BookingStatus.confirmed
                  ? Icons.confirmation_number_outlined
                  : Icons.hourglass_top_rounded,
              expanded: false,
              dark: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              onPressed: () => context.push('/trip/${trip.id}/tracking'),
            )
          else
            GlowButton(
              label: trip.isFull ? 'Complet' : 'Réserver',
              expanded: false,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 56, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text('Trajet introuvable', style: AppTextStyles.title2),
              const SizedBox(height: 4),
              Text('Il a peut-être été annulé par le chauffeur.', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              GlowButton(
                label: 'Retour',
                dark: true,
                expanded: false,
                onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
