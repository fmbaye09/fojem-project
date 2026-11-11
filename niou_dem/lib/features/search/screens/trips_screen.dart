import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/widgets/option_sheet.dart';
import '../../../core/widgets/trip_card.dart';
import '../../../models/trip.dart';
import '../../../providers/search_provider.dart';
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
        _Sort.time => 'Plus tôt',
        _Sort.price => 'Moins cher',
        _Sort.rating => 'Mieux noté',
      };
}

/// Trajets pour la recherche faite depuis l'accueil ([SearchProvider]) :
/// en-tête du trajet recherché, bande des jours (avec le nombre de trajets
/// de chacun, pour changer de jour sans revenir en arrière), tri et filtres,
/// puis les trajets du jour choisi.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  State<SearchResultsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<SearchResultsScreen> {
  final _repository = TripRepository();
  static const _days = 14;

  late final GeoLocation _origin;
  late final GeoLocation _destination;
  late final String _departure;
  late final String _arrival;
  late DateTime _date;

  bool _isLoading = true;
  bool _hasError = false;

  /// Trajets de l'itinéraire, tous jours confondus (non complets).
  List<Trip> _routeTrips = [];
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

  /// Recherche géographique (`GET /trips/search`), tous jours confondus ; le
  /// jour choisi ne fait que filtrer, sans nouvel appel.
  Future<void> _load() async {
    try {
      final result = await _repository
          .searchWithSuggestions(origin: _origin, destination: _destination)
          .timeout(const Duration(seconds: 15));
      final routeTrips = result.trips.where((trip) => !trip.isFull).toList();
      final suggestions = <String, Trip>{
        for (final trip in result.suggestions.where((t) => !t.isFull))
          if (!routeTrips.any((r) => r.id == trip.id)) trip.id: trip,
      };
      if (!mounted) return;
      setState(() {
        _routeTrips = routeTrips;
        _suggestions = suggestions.values.toList();
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

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _isSameDay(DateTime a, DateTime b) => _day(a) == _day(b);

  int _countOn(DateTime day) => _routeTrips.where((t) => _isSameDay(boardingTime(t), day)).length;

  /// Premier jour suivant qui a des trajets, pour le proposer quand le jour
  /// choisi n'en a pas.
  DateTime? get _nextDayWithTrips {
    final days = _routeTrips.map((t) => _day(boardingTime(t))).where((d) => d.isAfter(_day(_date))).toList()
      ..sort();
    return days.isEmpty ? null : days.first;
  }

  void _selectDay(DateTime day) {
    setState(() => _date = day);
    context.read<SearchProvider>().setDate(day);
  }

  bool get _hasFilters => _timeSlot != _TimeSlot.any || _maxPrice != null || _minSeats > 1;

  List<Trip> get _dayTrips => _routeTrips.where((t) => _isSameDay(boardingTime(t), _date)).toList();

  List<Trip> get _visibleTrips {
    final result = _dayTrips
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
        result.sort((a, b) => (b.driver?.rating ?? 0).compareTo(a.driver?.rating ?? 0));
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
        (_Sort.time, 'Départ le plus tôt'),
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
    final today = _day(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  GlassIconButton(icon: Icons.arrow_back_rounded, onPressed: _back, tooltip: 'Retour'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RouteSummary(
                      departure: _departure,
                      arrival: _arrival,
                      onTap: _back,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _days,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final day = today.add(Duration(days: i));
                  return _DayChip(
                    day: day,
                    count: _isLoading ? null : _countOn(day),
                    selected: _isSameDay(day, _date),
                    onTap: () => _selectDay(day),
                  );
                },
              ),
            ),
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  _FilterChip(icon: Icons.sort_rounded, label: _sort.label, isActive: _sort != _Sort.time, onTap: _pickSort),
                  const SizedBox(width: 8),
                  _FilterChip(icon: Icons.schedule_rounded, label: _timeSlot.label, isActive: _timeSlot != _TimeSlot.any, onTap: _pickTimeSlot),
                  const SizedBox(width: 8),
                  _FilterChip(
                    icon: Icons.sell_outlined,
                    label: _maxPrice == null ? 'Prix' : '≤ ${formatFcfa(_maxPrice!)}',
                    isActive: _maxPrice != null,
                    onTap: _pickPrice,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    icon: Icons.event_seat_outlined,
                    label: _minSeats > 1 ? '$_minSeats+ places' : 'Places',
                    isActive: _minSeats > 1,
                    onTap: _pickSeats,
                  ),
                  if (_hasFilters) ...[
                    const SizedBox(width: 8),
                    _FilterChip(icon: Icons.close_rounded, label: 'Effacer', isActive: false, showChevron: false, onTap: _clearFilters),
                  ],
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.ink,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (_isLoading) ...[
                      const TripCardSkeleton(),
                      const SizedBox(height: 12),
                      const TripCardSkeleton(),
                    ] else if (_hasError)
                      _Message(
                        icon: Icons.wifi_off_rounded,
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
                      if (_hasFilters && _dayTrips.isNotEmpty)
                        _Message(
                          icon: Icons.filter_alt_off_rounded,
                          title: 'Aucun trajet avec ces filtres',
                          body: '${_dayTrips.length} trajet${_dayTrips.length > 1 ? 's' : ''} ce jour-là sans filtre.',
                          actionLabel: 'Effacer les filtres',
                          onAction: _clearFilters,
                        )
                      else if (_nextDayWithTrips case final next?)
                        _Message(
                          icon: Icons.event_busy_rounded,
                          title: 'Aucun trajet ${_dayPhrase(_date)}',
                          body: 'Il y a des trajets $_departure → $_arrival ${_dayPhrase(next)}.',
                          actionLabel: 'Voir ${_dayPhrase(next)}',
                          onAction: () => _selectDay(next),
                        )
                      else
                        _Message(
                          icon: Icons.event_busy_rounded,
                          title: 'Aucun trajet pour le moment',
                          body: 'Personne ne propose encore $_departure → $_arrival. '
                              'Publiez une demande : les chauffeurs qui passent par là la verront.',
                          actionLabel: 'Demander ce trajet',
                          onAction: () => context.push(
                            '/ride-request/create?from=${Uri.encodeComponent(_departure)}&to=${Uri.encodeComponent(_arrival)}',
                          ),
                        ),
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Autres trajets proches', style: AppTextStyles.title2),
                        const SizedBox(height: 4),
                        Text('Départ ou arrivée un peu plus loin de vos points.', style: AppTextStyles.caption),
                        const SizedBox(height: 12),
                        for (final trip in _suggestions) ...[
                          TripCard(
                            trip: trip,
                            layout: TripCardLayout.schedule,
                            onTap: () => context.push(tripDetailLocation(trip)),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, left: 2),
                        child: Text(
                          '${trips.length} trajet${trips.length > 1 ? 's' : ''} ${_dayPhrase(_date)}',
                          style: AppTextStyles.bodySemibold.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      for (var i = 0; i < trips.length; i++) ...[
                        RiseIn(
                          delay: Duration(milliseconds: 40 * i),
                          child: TripCard(
                            trip: trips[i],
                            layout: TripCardLayout.schedule,
                            onTap: () => context.push(tripDetailLocation(trips[i])),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// « aujourd'hui », « demain », « le jeu. 14 nov. ».
  static String _dayPhrase(DateTime day) {
    final label = formatDayLabel(day);
    if (label == 'Aujourd’hui' || label == 'Demain') return label.toLowerCase();
    return 'le $label';
  }
}

/// Rappel du trajet recherché ; le toucher revient le modifier.
class _RouteSummary extends StatelessWidget {
  final String departure;
  final String arrival;
  final VoidCallback onTap;

  const _RouteSummary({required this.departure, required this.arrival, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Trajet recherché : $departure vers $arrival. Modifier',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Flexible(
                    child: Text(departure, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.textSecondary),
                  ),
                  Flexible(
                    child: Text(arrival, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Jour de la bande de dates, avec le nombre de trajets ce jour-là.
class _DayChip extends StatelessWidget {
  final DateTime day;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({required this.day, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = formatDayLabel(day);
    final title = label == 'Aujourd’hui' || label == 'Demain' ? label : DateFormat('EEE d', 'fr_FR').format(day);
    final fg = selected ? Colors.white : AppColors.textPrimary;
    final sub = count == null
        ? ' '
        : count == 0
            ? '–'
            : '$count trajet${count! > 1 ? 's' : ''}';
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${count ?? 0} trajet${(count ?? 0) > 1 ? 's' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.ink : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 76),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? AppColors.ink : AppColors.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: AppTextStyles.bodySemibold.copyWith(color: fg, fontWeight: FontWeight.w700, height: 1.2)),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : (count ?? 0) > 0
                            ? AppColors.success
                            : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
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

/// Puce de tri / filtre : blanche, pleine (bleu nuit) quand active.
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
    final fg = isActive ? Colors.white : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        color: isActive ? AppColors.ink : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: isActive ? AppColors.ink : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(label, style: AppTextStyles.bodySemibold.copyWith(color: fg, fontSize: 13.5)),
                if (showChevron) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(title, style: AppTextStyles.title2),
          const SizedBox(height: 4),
          Text(body, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          GlowButton(label: actionLabel, onPressed: onAction, dark: true),
        ],
      ),
    );
  }
}
