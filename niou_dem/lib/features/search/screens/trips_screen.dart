import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/option_sheet.dart';
import '../../../core/widgets/trip_card.dart';
import '../../../core/widgets/trust_banner.dart';
import '../../../models/trip.dart';
import '../../../providers/search_provider.dart';
import '../../../services/map/osm_map_service.dart';
import '../../../services/trip_repository.dart';

enum _TimeSlot { any, morning, afternoon, evening }

enum _Sort { time, price, rating }

extension on _TimeSlot {
  String get label => switch (this) {
        _TimeSlot.any => 'Départ',
        _TimeSlot.morning => 'Matin',
        _TimeSlot.afternoon => 'Après-midi',
        _TimeSlot.evening => 'Soir',
      };

  bool matches(DateTime t) => switch (this) {
        _TimeSlot.any => true,
        _TimeSlot.morning => t.hour < 12,
        _TimeSlot.afternoon => t.hour >= 12 && t.hour < 17,
        _TimeSlot.evening => t.hour >= 17,
      };
}

extension on _Sort {
  String get label => switch (this) {
        _Sort.time => 'Heure',
        _Sort.price => 'Prix',
        _Sort.rating => 'Note',
      };
}

/// Résultats de recherche, ouverts depuis « Rechercher un trajet » sur
/// l'accueil : en-tête du trajet recherché, rangée tri + filtres, carte de
/// l'itinéraire, trajets disponibles, bandeau de confiance.
///
/// Le trajet affiché est la dernière recherche faite depuis l'accueil
/// ([SearchProvider]), Dakar → Thiès aujourd'hui par défaut.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  State<SearchResultsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<SearchResultsScreen> {
  final _repository = TripRepository();

  late final GeoLocation _origin;
  late final GeoLocation _destination;
  late final String _departure;
  late final String _arrival;
  late final DateTime _date;

  bool _isLoading = true;
  bool _hasError = false;
  List<Trip> _trips = [];
  List<Trip> _suggestions = [];

  _TimeSlot _timeSlot = _TimeSlot.any;
  int? _maxPrice;
  int _minSeats = 1;
  _Sort _sort = _Sort.time;

  @override
  void initState() {
    super.initState();
    final search = context.read<SearchProvider>();
    _origin = search.origin ?? coordinatesForCity('Dakar');
    _destination = search.destination ?? coordinatesForCity('Thiès');
    _departure = _origin.shortLabel;
    _arrival = _destination.shortLabel;
    _date = search.date;
    _minSeats = search.passengers;
    _load();
  }

  /// Recherche géographique réelle (`GET /trips/search`) puis restriction au
  /// jour choisi côté client, avec suggestions d'alternatives si vide.
  Future<void> _load() async {
    try {
      final desiredOrigin = _origin;
      final desiredDestination = _destination;
      final searchResult = await _repository
          .searchWithSuggestions(origin: desiredOrigin, destination: desiredDestination)
          .timeout(const Duration(seconds: 15));

      final matched = searchResult.trips
          .where((trip) => !trip.isFull && _isSameDay(boardingTime(trip), _date))
          .toList();

      final otherDays = searchResult.trips
          .where((trip) => !trip.isFull && !_isSameDay(boardingTime(trip), _date))
          .toList();

      final combinedSuggestions = [
        ...searchResult.suggestions.where((t) => !t.isFull),
        ...otherDays,
      ];

      final uniqueSuggestions = <String, Trip>{};
      for (final s in combinedSuggestions) {
        if (!matched.any((m) => m.id == s.id)) {
          uniqueSuggestions[s.id] = s;
        }
      }

      if (!mounted) return;
      setState(() {
        _trips = matched;
        _suggestions = uniqueSuggestions.values.toList();
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

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _hasFilters =>
      _timeSlot != _TimeSlot.any || _maxPrice != null || _minSeats > 1;

  List<Trip> get _visibleTrips {
    final result = _trips
        .where((t) =>
            _timeSlot.matches(boardingTime(t)) &&
            (_maxPrice == null || t.segment().pricePerSeat <= _maxPrice!) &&
            t.availableSeats >= _minSeats)
        .toList();
    switch (_sort) {
      case _Sort.time:
        result.sort((a, b) => boardingTime(a).compareTo(boardingTime(b)));
      case _Sort.price:
        result.sort((a, b) => a.segment().pricePerSeat.compareTo(b.segment().pricePerSeat));
      case _Sort.rating:
        result.sort(
            (a, b) => (b.driver?.rating ?? 0).compareTo(a.driver?.rating ?? 0));
    }
    return result;
  }

  void _clearFilters() => setState(() {
        _timeSlot = _TimeSlot.any;
        _maxPrice = null;
        _minSeats = 1;
      });

  Future<void> _pickSort() async {
    final value = await showOptionSheet<_Sort>(
      context,
      title: 'Trier par',
      selected: _sort,
      options: const [
        (_Sort.time, 'Heure de départ'),
        (_Sort.price, 'Prix le plus bas'),
        (_Sort.rating, 'Meilleure note'),
      ],
    );
    if (value != null) setState(() => _sort = value);
  }

  Future<void> _pickTimeSlot() async {
    final value = await showOptionSheet<_TimeSlot>(
      context,
      title: 'Heure de départ',
      selected: _timeSlot,
      options: const [
        (_TimeSlot.any, 'Toute la journée'),
        (_TimeSlot.morning, 'Matin · avant 12h'),
        (_TimeSlot.afternoon, 'Après-midi · 12h – 17h'),
        (_TimeSlot.evening, 'Soir · après 17h'),
      ],
    );
    if (value != null) setState(() => _timeSlot = value);
  }

  Future<void> _pickPrice() async {
    final value = await showOptionSheet<int>(
      context,
      title: 'Prix maximum par place',
      selected: _maxPrice ?? 0,
      options: const [
        (0, 'Tous les prix'),
        (2000, 'Jusqu’à 2 000 FCFA'),
        (3000, 'Jusqu’à 3 000 FCFA'),
        (5000, 'Jusqu’à 5 000 FCFA'),
      ],
    );
    if (value != null) setState(() => _maxPrice = value == 0 ? null : value);
  }

  Future<void> _pickSeats() async {
    final value = await showOptionSheet<int>(
      context,
      title: 'Places nécessaires',
      selected: _minSeats,
      options: const [
        (1, '1 place'),
        (2, '2 places'),
        (3, '3 places'),
        (4, '4 places ou plus'),
      ],
    );
    if (value != null) setState(() => _minSeats = value);
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = _visibleTrips;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BrandHeaderLayout(
        onRefresh: _load,
        overlap: 0,
        padding: EdgeInsets.zero,
        header: BrandHeader(
          title: '$_departure → $_arrival',
          subtitle: formatDayLabel(_date),
          onBack: _back,
          trailing: const NotificationBellButton(onBrand: true),
          overlap: 28,
        ),
        children: [
          // Tri et filtres sur une seule rangée défilante, sous l'en-tête.
          RiseIn(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  _FilterChip(
                    icon: Icons.swap_vert_rounded,
                    label: 'Trier : ${_sort.label}',
                    isActive: _sort != _Sort.time,
                    onTap: _pickSort,
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    icon: Icons.schedule_rounded,
                    label: _timeSlot.label,
                    isActive: _timeSlot != _TimeSlot.any,
                    onTap: _pickTimeSlot,
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    icon: Icons.sell_outlined,
                    label: _maxPrice == null
                        ? 'Prix max'
                        : '≤ ${formatFcfa(_maxPrice!)}',
                    isActive: _maxPrice != null,
                    onTap: _pickPrice,
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    icon: Icons.groups_rounded,
                    label: _minSeats > 1 ? '$_minSeats+ places' : 'Places',
                    isActive: _minSeats > 1,
                    onTap: _pickSeats,
                  ),
                  if (_hasFilters) ...[
                    const SizedBox(width: 10),
                    _FilterChip(
                      icon: Icons.close_rounded,
                      label: 'Effacer',
                      isActive: false,
                      showChevron: false,
                      onTap: _clearFilters,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          const SizedBox(height: 6),
          RiseIn(
            delay: const Duration(milliseconds: 80),
            child: _RouteMap(origin: _origin, destination: _destination),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: Text('Trajets disponibles', style: AppTextStyles.title2)),
              if (!_isLoading && !_hasError)
                Text('${trips.length} trajet${trips.length > 1 ? 's' : ''}', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading) ...[
            const TripCardSkeleton(),
            const SizedBox(height: 16),
            const TripCardSkeleton(),
          ] else if (_hasError)
            _Message(
              title: 'Impossible de charger les trajets',
              body: 'Vérifiez votre connexion puis réessayez.',
              actionLabel: 'Réessayer',
              onAction: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _load();
              },
            )
          else if (trips.isEmpty) ...[
            _hasFilters
                ? _Message(
                    title: 'Aucun trajet avec ces filtres',
                    body: '${_trips.length} trajet${_trips.length > 1 ? 's' : ''} '
                        'disponible${_trips.length > 1 ? 's' : ''} sans filtre.',
                    actionLabel: 'Effacer les filtres',
                    onAction: _clearFilters,
                  )
                : _Message(
                    title: 'Aucun trajet direct trouvé',
                    body: 'Personne ne propose encore $_departure → $_arrival '
                        '${formatDayLabel(_date).toLowerCase()}. Créez une demande de trajet '
                        'ou réservez un trajet suggéré ci-dessous.',
                    actionLabel: 'Créer une demande de trajet',
                    onAction: () => context.push('/ride-request/create?from=$_departure&to=$_arrival'),
                  ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Autres trajets disponibles', style: AppTextStyles.title2)),
                ],
              ),
              const SizedBox(height: 12),
              for (final trip in _suggestions) ...[
                TripCard(
                  trip: trip,
                  layout: TripCardLayout.schedule,
                  onTap: () => context.push(tripDetailLocation(trip)),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ] else
            for (var i = 0; i < trips.length; i++) ...[
              RiseIn(
                delay: Duration(milliseconds: 60 * i),
                child: TripCard(
                  trip: trips[i],
                  layout: TripCardLayout.schedule,
                  onTap: () => context.push(tripDetailLocation(trips[i])),
                ),
              ),
              const SizedBox(height: 16),
            ],
          const SizedBox(height: 4),
          const TrustBanner(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Puce de tri / filtre : en relief, teintée quand active.
class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool showChevron;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.primary : AppColors.textPrimary;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.bodySemibold.copyWith(color: color, fontSize: 13.5)),
        if (showChevron) ...[
          const SizedBox(width: 2),
          Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: color),
        ],
      ],
    );
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    return Semantics(
      button: true,
      selected: isActive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: isActive
            ? Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: content,
              )
            : NeuBox(small: true, radius: 999, padding: padding, child: content),
      ),
    );
  }
}

class _RouteMap extends StatefulWidget {
  final GeoLocation origin;
  final GeoLocation destination;

  const _RouteMap({required this.origin, required this.destination});

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  final _controller = MapController();
  late final ll.LatLng _origin;
  late final ll.LatLng _destination;
  late List<ll.LatLng> _path;

  @override
  void initState() {
    super.initState();
    final o = widget.origin;
    final d = widget.destination;
    _origin = ll.LatLng(o.lat, o.lng);
    _destination = ll.LatLng(d.lat, d.lng);
    _path = [_origin, _destination];
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    try {
      final route = await OsmMapService()
          .getRoute(widget.origin,
              widget.destination)
          .timeout(const Duration(seconds: 8));
      if (route == null || route.polyline.length < 2 || !mounted) return;
      setState(() =>
          _path = [for (final p in route.polyline) ll.LatLng(p.lat, p.lng)]);
    } catch (_) {
      // Ligne droite conservée : la carte reste lisible sans le tracé exact.
    }
  }

  CameraFit get _fit => CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([_origin, _destination]),
        padding: const EdgeInsets.fromLTRB(56, 56, 72, 56),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(28)),
        boxShadow: AppColors.neuShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCameraFit: _fit,
              backgroundColor: const Color(0xFFF2F0EB),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'sn.fojem.app',
                // Fond OSM adouci (moins saturé, plus clair) pour que le
                // tracé et les repères restent l'information principale.
                tileBuilder: (context, tile, _) => ColorFiltered(
                  colorFilter: _softMapFilter,
                  child: tile,
                ),
              ),
              PolylineLayer(polylines: [
                Polyline(
                  points: _path,
                  color: AppColors.textPrimary,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  strokeJoin: StrokeJoin.round,
                ),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: _origin,
                  width: 110,
                  height: 64,
                  child: _CityMarker(city: widget.origin.shortLabel, isOrigin: true),
                ),
                Marker(
                  point: _destination,
                  width: 110,
                  height: 96,
                  child: _CityMarker(city: widget.destination.shortLabel, isOrigin: false),
                ),
              ]),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: AppColors.surface,
              elevation: 2,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _controller.fitCamera(_fit),
                borderRadius: BorderRadius.circular(10),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Tooltip(
                    message: 'Recentrer sur le trajet',
                    child: Icon(Icons.my_location_rounded,
                        size: 22, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 6,
            child: Text(
              '© OpenStreetMap',
              style: AppTextStyles.caption
                  .copyWith(fontSize: 9, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// Saturation ~55 % puis éclaircissement léger vers le blanc.
const _softMapFilter = ColorFilter.matrix(<double>[
  0.62, 0.25, 0.04, 0, 34, //
  0.12, 0.76, 0.04, 0, 34, //
  0.12, 0.25, 0.54, 0, 34, //
  0, 0, 0, 1, 0,
]);

/// Repère de ville centré sur sa coordonnée : anneau orange (départ) ou
/// épingle orange dont la pointe touche le point (arrivée), nom dessous.
class _CityMarker extends StatelessWidget {
  final String city;
  final bool isOrigin;

  const _CityMarker({required this.city, required this.isOrigin});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      city,
      textAlign: TextAlign.center,
      style: AppTextStyles.bodySemibold.copyWith(
        fontSize: 15,
        height: 1.1,
        shadows: const [
          Shadow(color: Colors.white, blurRadius: 4),
          Shadow(color: Colors.white, blurRadius: 8),
        ],
      ),
    );

    if (isOrigin) {
      return Stack(
        children: [
          Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 3),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, top: 46, child: label),
        ],
      );
    }

    // Boîte de 96 de haut centrée sur le point : l'épingle (40) occupe
    // 8→48 pour que sa pointe tombe au centre (48).
    return Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 8,
          child: Icon(Icons.location_on, size: 42, color: AppColors.primary),
        ),
        Positioned(left: 0, right: 0, top: 54, child: label),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _Message({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassPanel(
        radius: 24,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: NeuBox(
                small: true,
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                onTap: onAction,
                child: Text(actionLabel, style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
