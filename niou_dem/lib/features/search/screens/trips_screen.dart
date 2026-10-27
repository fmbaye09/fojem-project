import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
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
        _TimeSlot.any => 'Heure',
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

/// Onglet Trajets — fidèle à la maquette "Dakar → Thiès" : en-tête du
/// trajet recherché, filtres Heure / Prix / Places, carte de l'itinéraire,
/// liste des trajets disponibles triable, bandeau de confiance.
///
/// Le trajet affiché est la dernière recherche faite depuis l'accueil
/// ([SearchProvider]), Dakar → Thiès aujourd'hui par défaut.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final _repository = TripRepository();

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
    _departure = search.departure ?? 'Dakar';
    _arrival = search.arrival ?? 'Thiès';
    _date = search.date;
    _minSeats = search.passengers;
    _load();
  }

  /// Recherche géographique réelle (`GET /trips/search`) puis restriction au
  /// jour choisi côté client, avec suggestions d'alternatives si vide.
  Future<void> _load() async {
    try {
      final desiredOrigin = coordinatesForCity(_departure);
      final desiredDestination = coordinatesForCity(_arrival);
      final searchResult = await _repository
          .searchWithSuggestions(origin: desiredOrigin, destination: desiredDestination)
          .timeout(const Duration(seconds: 15));

      final matched = searchResult.trips
          .where((trip) => !trip.isFull && _isSameDay(trip.departureTime, _date))
          .toList();

      final otherDays = searchResult.trips
          .where((trip) => !trip.isFull && !_isSameDay(trip.departureTime, _date))
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
            _timeSlot.matches(t.departureTime) &&
            (_maxPrice == null || t.pricePerSeat <= _maxPrice!) &&
            t.availableSeats >= _minSeats)
        .toList();
    switch (_sort) {
      case _Sort.time:
        result.sort((a, b) => a.departureTime.compareTo(b.departureTime));
      case _Sort.price:
        result.sort((a, b) => a.pricePerSeat.compareTo(b.pricePerSeat));
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
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _Header(
                departure: _departure,
                arrival: _arrival,
                dateLabel: formatDayLabel(_date),
                onBack: _back,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _FilterButton(
                      icon: Icons.schedule_rounded,
                      label: _timeSlot.label,
                      isActive: _timeSlot != _TimeSlot.any,
                      onTap: _pickTimeSlot,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FilterButton(
                      icon: Icons.sell_outlined,
                      label: _maxPrice == null
                          ? 'Prix'
                          : '≤ ${formatFcfa(_maxPrice!).replaceAll(' FCFA', '')}',
                      isActive: _maxPrice != null,
                      onTap: _pickPrice,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FilterButton(
                      icon: Icons.directions_car_outlined,
                      label: _minSeats > 1 ? '$_minSeats+ places' : 'Places',
                      isActive: _minSeats > 1,
                      onTap: _pickSeats,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _RouteMap(departure: _departure, arrival: _arrival),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: Text('Trajets disponibles',
                          style: AppTextStyles.title1.copyWith(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    _SortMenu(
                      sort: _sort,
                      compact: constraints.maxWidth < 340,
                      onChanged: (s) => setState(() => _sort = s),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_isLoading) ...[
                const TripCardSkeleton(),
                const SizedBox(height: 14),
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
                        body:
                            '${_trips.length} trajet${_trips.length > 1 ? 's' : ''} '
                            'disponible${_trips.length > 1 ? 's' : ''} sans filtre.',
                        actionLabel: 'Effacer les filtres',
                        onAction: _clearFilters,
                      )
                    : _Message(
                        title: 'Aucun trajet direct trouvé',
                        body:
                            'Personne ne propose encore $_departure → $_arrival '
                            '${formatDayLabel(_date).toLowerCase()}. Vous pouvez créer une demande de trajet ou réserver un trajet suggéré ci-dessous.',
                        actionLabel: 'Créer une demande de trajet',
                        onAction: () => context.push(
                            '/ride-request/create?from=$_departure&to=$_arrival'),
                      ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Suggestions d\'autres trajets disponibles',
                        style: AppTextStyles.title2.copyWith(fontSize: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final trip in _suggestions) ...[
                    TripCard(
                      trip: trip,
                      layout: TripCardLayout.schedule,
                      onTap: () => context.push('/trip/${trip.id}'),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ]
              else
                for (final trip in trips) ...[
                  TripCard(
                    trip: trip,
                    layout: TripCardLayout.schedule,
                    onTap: () => context.push('/trip/${trip.id}'),
                  ),
                  const SizedBox(height: 14),
                ],
              const SizedBox(height: 6),
              const TrustBanner(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const TravelerBottomNavBar(current: ClientTab.trips),
    );
  }
}

class _Header extends StatelessWidget {
  final String departure;
  final String arrival;
  final String dateLabel;
  final VoidCallback onBack;

  const _Header({
    required this.departure,
    required this.arrival,
    required this.dateLabel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        AppTextStyles.display.copyWith(fontSize: 23, height: 1.15);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_rounded,
              size: 26, color: AppColors.textPrimary),
          style: IconButton.styleFrom(padding: EdgeInsets.zero),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(departure, style: titleStyle),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Icon(Icons.arrow_forward_rounded,
                            size: 22, color: AppColors.primary),
                      ),
                      Text(arrival, style: titleStyle),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        size: 18, color: AppColors.textPrimary),
                    const SizedBox(width: 8),
                    Text(dateLabel,
                        style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.textSecondary, height: 1.2)),
                  ],
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: () => context.push('/notifications'),
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded,
              size: 26, color: AppColors.textPrimary),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.primary : AppColors.textPrimary;
    return Material(
      color: isActive ? AppColors.primarySurface : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusButton),
        side:
            BorderSide(color: isActive ? AppColors.primary : AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusButton),
        ),
        child: SizedBox(
          height: 44,
          child: LayoutBuilder(
            // Sous ~110 dp de large (écrans 360 dp), l'icône cède sa place
            // au libellé plutôt que de le tronquer.
            builder: (context, constraints) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (constraints.maxWidth >= 110) ...[
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        color: color,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final _Sort sort;
  final ValueChanged<_Sort> onChanged;

  /// Écrans étroits : icône de tri à la place du libellé "Trier par :".
  final bool compact;

  const _SortMenu({
    required this.sort,
    required this.onChanged,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Sort>(
      initialValue: sort,
      onSelected: onChanged,
      tooltip: 'Trier',
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (_) => [
        for (final s in _Sort.values)
          PopupMenuItem(
            value: s,
            child: Text(
              s.label,
              style: AppTextStyles.body.copyWith(
                fontWeight: s == sort ? FontWeight.w600 : FontWeight.w400,
                color: s == sort ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact) ...[
              const Icon(Icons.sort_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
            ] else
              Text('Trier par : ',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary, fontSize: 14)),
            Text(sort.label,
                style: AppTextStyles.bodySemibold
                    .copyWith(color: AppColors.primary, fontSize: 14)),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// Carte de l'itinéraire : tracé routier réel (OSRM) entre les deux villes,
/// ligne droite en attendant ou si le service ne répond pas. Le bouton en
/// haut à droite recadre sur le trajet après un déplacement.
class _RouteMap extends StatefulWidget {
  final String departure;
  final String arrival;

  const _RouteMap({required this.departure, required this.arrival});

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
    final o = coordinatesForCity(widget.departure);
    final d = coordinatesForCity(widget.arrival);
    _origin = ll.LatLng(o.lat, o.lng);
    _destination = ll.LatLng(d.lat, d.lng);
    _path = [_origin, _destination];
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    try {
      final route = await OsmMapService()
          .getRoute(coordinatesForCity(widget.departure),
              coordinatesForCity(widget.arrival))
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
      decoration: AppColors.softCardDecoration,
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
                  child: _CityMarker(city: widget.departure, isOrigin: true),
                ),
                Marker(
                  point: _destination,
                  width: 110,
                  height: 96,
                  child: _CityMarker(city: widget.arrival, isOrigin: false),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppColors.softCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.bodyLargeSemibold),
          const SizedBox(height: 6),
          Text(body,
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppSpacing.borderRadiusButton),
              ),
              textStyle: AppTextStyles.bodySemibold,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
