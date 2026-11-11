import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../../../core/events/data_refresh.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../../../core/widgets/fojem_map.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/location_picker_screen.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/widgets/trip_card.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../services/booking_repository.dart';
import '../../../services/map/place_search.dart';
import '../../../services/trip_repository.dart';

/// Accueil voyageur, comme une appli de VTC : la carte en plein écran (votre
/// position, les départs proches), et une feuille en bas pour dire où l'on
/// va. Choisir une destination ouvre aussitôt les trajets disponibles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutoRefresh<HomeScreen> {
  @override
  Future<void> onAutoRefresh() => _loadNearby(silent: true);

  bool _isLoading = true;
  bool _hasError = false;
  List<Trip> _nearby = [];
  Booking? _activeBooking;
  Timer? _pollTimer;

  late final SearchProvider _search;

  /// Points de la dernière recherche lancée : la réponse d'une recherche
  /// dont le départ ou l'arrivée a changé depuis est ignorée.
  bool _requested = false;
  GeoLocation? _loadedOrigin;
  GeoLocation? _loadedDestination;

  @override
  void initState() {
    super.initState();
    _search = context.read<SearchProvider>()..addListener(_onSearchChanged);
    // Après la première image : la localisation notifie le provider.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (shouldPoll(context)) _loadNearby(silent: true);
    });
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Le départ par défaut est la position actuelle : les prochains départs
  /// sont ceux qui passent près du passager.
  Future<void> _start() async {
    await _search.locateOrigin();
    if (mounted && !_requested) await _loadNearby();
  }

  static bool _samePoint(GeoLocation? a, GeoLocation? b) => a?.lat == b?.lat && a?.lng == b?.lng;

  bool _isLatest(GeoLocation? origin, GeoLocation? destination) =>
      _samePoint(origin, _loadedOrigin) && _samePoint(destination, _loadedDestination);

  void _onSearchChanged() {
    if (!_isLatest(_search.origin, _search.destination)) _loadNearby(silent: true);
  }

  Future<void> _loadNearby({bool silent = false}) async {
    final origin = _search.origin;
    final destination = _search.destination;
    _requested = true;
    _loadedOrigin = origin;
    _loadedDestination = destination;

    final userId = context.read<AppProvider>().user?.id;
    Booking? activeBooking;
    if (userId != null) {
      try {
        final bookings = await BookingRepository().fetchForPassenger(userId);
        final activeList = bookings
            .where((b) => b.status == BookingStatus.pending || b.status == BookingStatus.confirmed)
            .toList();
        if (activeList.isNotEmpty) activeBooking = activeList.first;
      } catch (_) {}
    }

    try {
      final trips = await TripRepository()
          .search(origin: origin, destination: destination)
          .timeout(const Duration(seconds: 15));
      final nearby = trips.where((t) => !t.isFull).toList()
        ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
      if (!mounted || !_isLatest(origin, destination)) return;
      setState(() {
        _activeBooking = activeBooking;
        _nearby = nearby.take(5).toList();
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted || !_isLatest(origin, destination)) return;
      setState(() {
        _activeBooking = activeBooking;
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  // ─── Recherche ──────────────────────────────────────────────────────────

  Future<GeoLocation?> _pickPlace({required bool isDeparture}) {
    return Navigator.of(context).push<GeoLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: isDeparture ? 'D’où partez-vous ?' : 'Où allez-vous ?',
          initial: isDeparture ? _search.origin : _search.destination,
          showCurrentLocation: isDeparture || _search.origin == null,
        ),
      ),
    );
  }

  Future<void> _changeOrigin() async {
    final picked = await _pickPlace(isDeparture: true);
    if (picked != null) _search.setOrigin(picked);
  }

  /// Destination choisie : on ouvre les trajets, après avoir demandé le
  /// départ si la position n'est pas connue.
  Future<void> _chooseDestination([GeoLocation? destination]) async {
    final picked = destination ?? await _pickPlace(isDeparture: false);
    if (!mounted || picked == null) return;
    _search.setDestination(picked);
    await _openResults();
  }

  Future<void> _openResults() async {
    if (_search.destination == null) return _chooseDestination();
    if (_search.origin == null) {
      final origin = await _pickPlace(isDeparture: true);
      if (!mounted || origin == null) return;
      _search.setOrigin(origin);
    }
    if (mounted && _search.hasSearch) context.push('/search');
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _search.date.isAfter(today.add(const Duration(days: 1))) ? _search.date : today.add(const Duration(days: 2)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      locale: const Locale('fr', 'FR'),
      helpText: 'Date du voyage',
    );
    if (picked != null) _search.setDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final user = context.watch<AppProvider>().user;
    final firstName = user?.name.trim().isNotEmpty == true ? user!.name.trim().split(RegExp(r'\s+')).first : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _HomeMap(
              origin: search.origin,
              trips: _nearby,
              onTripTap: (trip) => context.push(tripDetailLocation(trip)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _FloatingLabel(text: firstName == null ? 'Bonjour' : 'Bonjour, $firstName'),
                  const Spacer(),
                  DecoratedBox(
                    decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: AppColors.floatingShadow),
                    child: const NotificationBellButton(onBrand: true),
                  ),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.42,
            maxChildSize: 1,
            snap: true,
            snapSizes: const [0.6],
            builder: (context, controller) => DecoratedBox(
              decoration: AppColors.modalDecoration,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  const _Handle(),
                  if (_activeBooking != null) ...[
                    _ActiveBookingCard(booking: _activeBooking!),
                    const SizedBox(height: 16),
                  ],
                  Semantics(header: true, child: Text('Où allez-vous ?', style: AppTextStyles.display.copyWith(fontSize: 26))),
                  const SizedBox(height: 14),
                  _RouteFields(
                    departure: search.departure,
                    arrival: search.arrival,
                    isLocating: search.isLocating,
                    departureIsHere: search.isCurrentPosition(search.origin),
                    onDeparture: _changeOrigin,
                    onArrival: _chooseDestination,
                    onSwap: search.origin != null || search.destination != null ? search.swap : null,
                  ),
                  const SizedBox(height: 12),
                  _DateChips(date: search.date, onDate: search.setDate, onPickDate: _pickDate),
                  if (search.hasSearch) ...[
                    const SizedBox(height: 16),
                    GlowButton(
                      label: 'Voir les trajets',
                      leadingIcon: Icons.search_rounded,
                      onPressed: _openResults,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _PopularDestinations(
                    exclude: search.origin?.locality,
                    onPick: (place) => _chooseDestination(place.location),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    child: Text(
                      search.destination == null ? 'Départs près de vous' : 'Trajets vers ${search.arrival}',
                      style: AppTextStyles.title2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading) ...[
                    const TripCardSkeleton(),
                    const SizedBox(height: 12),
                    const TripCardSkeleton(),
                  ] else if (_hasError)
                    _Notice(
                      icon: Icons.wifi_off_rounded,
                      text: 'Impossible de charger les trajets.',
                      action: 'Réessayer',
                      onAction: _loadNearby,
                    )
                  else if (_nearby.isEmpty)
                    _Notice(
                      icon: Icons.event_busy_rounded,
                      text: search.destination != null
                          ? 'Aucun trajet prévu sur cet itinéraire pour le moment.'
                          : search.origin != null
                              ? 'Aucun départ prévu près de vous pour le moment.'
                              : 'Aucun trajet prévu pour le moment.',
                      action: 'Demander un trajet',
                      onAction: () => context.push('/ride-request/create'),
                    )
                  else
                    for (var i = 0; i < _nearby.length; i++) ...[
                      RiseIn(
                        delay: Duration(milliseconds: 40 * i),
                        child: TripCard(
                          trip: _nearby[i],
                          onTap: () => context.push(tripDetailLocation(_nearby[i])),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const TravelerBottomNavBar(current: ClientTab.home),
    );
  }
}

// ─── Carte ────────────────────────────────────────────────────────────────

/// Carte d'arrière-plan : la position du passager et l'heure des départs
/// proches, posées sur leur point de rendez-vous.
class _HomeMap extends StatefulWidget {
  final GeoLocation? origin;
  final List<Trip> trips;
  final ValueChanged<Trip> onTripTap;

  const _HomeMap({required this.origin, required this.trips, required this.onTripTap});

  @override
  State<_HomeMap> createState() => _HomeMapState();
}

class _HomeMapState extends State<_HomeMap> {
  static const _dakar = ll.LatLng(14.6928, -17.4467);
  final _controller = MapController();
  bool _ready = false;

  ll.LatLng get _center {
    final origin = widget.origin;
    return origin == null ? _dakar : ll.LatLng(origin.lat, origin.lng);
  }

  @override
  void didUpdateWidget(covariant _HomeMap old) {
    super.didUpdateWidget(old);
    final moved = old.origin?.lat != widget.origin?.lat || old.origin?.lng != widget.origin?.lng;
    // La carte remonte le centre au-dessus de la feuille du bas.
    if (moved && _ready) _controller.move(_shifted(_center), 13);
  }

  ll.LatLng _shifted(ll.LatLng center) => ll.LatLng(center.latitude - 0.03, center.longitude);

  @override
  Widget build(BuildContext context) {
    final origin = widget.origin;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _shifted(_center),
        initialZoom: 13,
        onMapReady: () => _ready = true,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        const FojemTileLayer(),
        MarkerLayer(
          markers: [
            // Dessinée d'abord : les départs, souvent tout près, restent lisibles.
            if (origin != null)
              Marker(point: ll.LatLng(origin.lat, origin.lng), width: 28, height: 28, child: const MyPositionDot()),
            for (final trip in widget.trips)
              if (trip.segment().boarding case final stop?)
                Marker(
                  point: ll.LatLng(stop.lat, stop.lng),
                  width: 92,
                  height: 36,
                  child: DeparturePin(
                    label: DateFormat('HH:mm').format(boardingTime(trip)),
                    onTap: () => widget.onTripTap(trip),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _FloatingLabel extends StatelessWidget {
  final String text;

  const _FloatingLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppColors.floatingShadow,
      ),
      child: Text(text, style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        width: 40,
        height: 4,
        decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

// ─── Feuille de recherche ─────────────────────────────────────────────────

/// Départ et arrivée, l'un sous l'autre, reliés comme sur un itinéraire ;
/// chaque ligne ouvre la recherche de lieu.
class _RouteFields extends StatelessWidget {
  final String? departure;
  final String? arrival;
  final bool isLocating;
  final bool departureIsHere;
  final VoidCallback onDeparture;
  final VoidCallback onArrival;
  final VoidCallback? onSwap;

  const _RouteFields({
    required this.departure,
    required this.arrival,
    required this.isLocating,
    required this.departureIsHere,
    required this.onDeparture,
    required this.onArrival,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _PlaceRow(
                  leading: departureIsHere
                      ? const Icon(Icons.my_location_rounded, size: 18, color: AppColors.ink)
                      : const _RouteDot(filled: false),
                  label: 'Départ',
                  value: departure,
                  placeholder: isLocating ? 'Localisation en cours…' : 'D’où partez-vous ?',
                  onTap: onDeparture,
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 48),
                  child: Divider(color: AppColors.borderStrong),
                ),
                _PlaceRow(
                  leading: const _RouteDot(filled: true),
                  label: 'Arrivée',
                  value: arrival,
                  placeholder: 'Choisir la destination',
                  emphasize: arrival == null,
                  onTap: onArrival,
                ),
              ],
            ),
          ),
          if (onSwap != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                tooltip: 'Inverser départ et arrivée',
                onPressed: onSwap,
                icon: const Icon(Icons.swap_vert_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteDot extends StatelessWidget {
  final bool filled;

  const _RouteDot({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: filled ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: filled ? BorderRadius.circular(3) : null,
        color: filled ? AppColors.brand : AppColors.surface,
        border: Border.all(color: filled ? AppColors.brand : AppColors.ink, width: 2.5),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final String? value;
  final String placeholder;
  final bool emphasize;
  final VoidCallback onTap;

  const _PlaceRow({
    required this.leading,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label : ${value ?? placeholder}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 20, child: Center(child: leading)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
                      Text(
                        value ?? placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLargeSemibold.copyWith(
                          color: value == null && !emphasize ? AppColors.textSecondary : AppColors.textPrimary,
                          fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « Aujourd'hui », « Demain », ou une autre date au calendrier.
class _DateChips extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onDate;
  final VoidCallback onPickDate;

  const _DateChips({required this.date, required this.onDate, required this.onPickDate});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final offset = day.difference(today).inDays;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _Chip(label: 'Aujourd’hui', selected: offset <= 0, onTap: () => onDate(now)),
          const SizedBox(width: 8),
          _Chip(label: 'Demain', selected: offset == 1, onTap: () => onDate(today.add(const Duration(days: 1)))),
          const SizedBox(width: 8),
          _Chip(
            label: offset > 1 ? DateFormat('EEE d MMM', 'fr_FR').format(date) : 'Autre date',
            icon: Icons.calendar_today_rounded,
            selected: offset > 1,
            onTap: onPickDate,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.ink : AppColors.borderStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(label, style: AppTextStyles.bodySemibold.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grandes villes en un geste : la destination est choisie, les trajets
/// s'ouvrent.
class _PopularDestinations extends StatelessWidget {
  final String? exclude;
  final ValueChanged<PlaceSuggestion> onPick;

  const _PopularDestinations({required this.exclude, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final here = exclude == null ? null : PlaceSearch.normalize(exclude!);
    final cities = PlaceSearch.cities().where((c) => PlaceSearch.normalize(c.title) != here).take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Destinations populaires', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cities.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _Chip(
              label: cities[i].title,
              icon: Icons.near_me_rounded,
              selected: false,
              onTap: () => onPick(cities[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  const _Notice({required this.icon, required this.text, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary))),
          const SizedBox(width: 8),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

/// Réservation en cours, en tête de la feuille : son état, le trajet,
/// l'heure ; ouvre le billet et le suivi.
class _ActiveBookingCard extends StatelessWidget {
  final Booking booking;

  const _ActiveBookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip;
    final isConfirmed = booking.status == BookingStatus.confirmed;
    final isBoarded = booking.isBoarded;
    final statusColor = isBoarded || isConfirmed ? AppColors.success : AppColors.amber;
    final statusSurface = isBoarded || isConfirmed ? AppColors.successSurface : AppColors.amberSurface;
    final statusLabel = isBoarded ? 'À bord' : (isConfirmed ? 'Réservation confirmée' : 'En attente du chauffeur');
    final when = booking.boardingStop?.scheduledAt ?? trip?.departureTime;

    return NeuBox(
      onTap: () => context.push('/trip/${booking.tripId}/tracking'),
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: statusSurface, borderRadius: BorderRadius.circular(12)),
            child: Icon(
              isConfirmed || isBoarded ? Icons.confirmation_number_rounded : Icons.hourglass_top_rounded,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusLabel, style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.w800)),
                Text(
                  '${booking.boardingStop?.name ?? trip?.departure ?? 'Départ'} → '
                  '${booking.alightingStop?.name ?? trip?.arrival ?? 'Arrivée'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w800),
                ),
                if (when != null)
                  Text(
                    '${formatDayLabel(when)} · ${DateFormat('HH:mm').format(when)} · ${booking.seatLabel}',
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
