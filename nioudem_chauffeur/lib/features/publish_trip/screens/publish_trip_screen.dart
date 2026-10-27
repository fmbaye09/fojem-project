import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/location_picker_screen.dart';
import '../../../core/widgets/option_sheet.dart';
import '../../../core/widgets/trip_card.dart' show formatDayLabel, formatFcfa;
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_text_field.dart';
import '../../../core/widgets/glow.dart';
import '../../../models/vehicle.dart';
import '../../../providers/app_provider.dart';
import '../../../services/map/map_service.dart';
import '../../../services/map/osm_map_service.dart';
import '../../../services/trip_repository.dart';
import '../../../services/vehicle_repository.dart';
import '../stop_plan.dart';

/// Publication de trajet chauffeur, en 3 étapes (design/screens/
/// fojem_publish_trip.png pour l'étape 1), sur le modèle BlaBlaCar : le
/// chauffeur fixe des points de rendez-vous précis (départ, arrêts, arrivée)
/// où les passagers viennent le retrouver.
///  1. Itinéraire : points de rendez-vous, date, heure, places, prix, véhicule.
///  2. Arrêts & horaires : tracé sur la carte, heure et prix de chaque point
///     calculés depuis l'itinéraire routier, prix ajustables.
///  3. Récapitulatif + publication.
class PublishTripScreen extends StatefulWidget {
  const PublishTripScreen({super.key});

  @override
  State<PublishTripScreen> createState() => _PublishTripScreenState();
}

class _PublishTripScreenState extends State<PublishTripScreen> {
  final MapService _mapService = OsmMapService();
  int _step = 0;

  // Étape 1
  GeoLocation? _origin;
  GeoLocation? _destination;
  final List<GeoLocation> _intermediate = [];
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 30);
  int _seats = 3;
  final _priceController = TextEditingController(text: '2000');
  List<Vehicle> _vehicles = const [];
  Vehicle? _vehicle;
  bool _isLoadingVehicle = true;

  // Étape 2
  RouteResult? _route;
  String? _routeKey;
  bool _isLoadingRoute = false;
  final Map<int, double> _priceOverrides = {};
  final _notesController = TextEditingController();

  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _loadVehicle();
  }

  Future<void> _loadVehicle() async {
    final driverId = context.read<AppProvider>().user?.id;
    if (driverId == null) {
      setState(() => _isLoadingVehicle = false);
      return;
    }
    final vehicles = await VehicleRepository().fetchAll();
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      final previousId = _vehicle?.id;
      _vehicle = vehicles.isEmpty
          ? null
          : vehicles.firstWhere(
              (v) => v.id == previousId,
              orElse: () => vehicles.first,
            );
      if (_vehicle != null && _seats > _vehicle!.totalSeats) {
        _seats = _vehicle!.totalSeats;
      }
      _isLoadingVehicle = false;
    });
  }

  Future<void> _selectVehicle() async {
    if (_vehicles.isEmpty) return;
    final selected = await _showVehicleSelector(
      context,
      vehicles: _vehicles,
      selectedId: _vehicle?.id,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _vehicle = selected;
      if (_seats > selected.totalSeats) {
        _seats = selected.totalSeats;
      }
    });
  }

  @override
  void dispose() {
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _fullPrice => double.tryParse(_priceController.text.replaceAll(' ', '')) ?? 0;

  DateTime get _departureAt => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  /// Départ → arrêts → arrivée, dans l'ordre de la route.
  List<GeoLocation> get _points => [
        if (_origin != null) _origin!,
        ..._intermediate,
        if (_destination != null) _destination!,
      ];

  /// Raison qui empêche de passer à l'étape suivante, ou `null`.
  String? get _step1Problem {
    if (_origin == null) return 'Choisissez votre point de départ.';
    if (_destination == null) return 'Choisissez votre point d’arrivée.';
    if (_origin!.distanceKm(_destination!) < 1) {
      return 'Le départ et l’arrivée sont trop proches.';
    }
    if (_vehicle == null) return 'Ajoutez votre véhicule.';
    if (_fullPrice <= 0) return 'Indiquez le prix par place.';
    if (!_departureAt.isAfter(DateTime.now())) return 'L’heure de départ est déjà passée.';
    return null;
  }

  List<PlannedStop> get _plannedStops => planStops(
        points: _points,
        legs: _route?.legs ?? const [],
        departure: _departureAt,
        fullPrice: _fullPrice,
        priceOverrides: _priceOverrides,
      );

  void _goNext() {
    if (_step == 0) {
      final problem = _step1Problem;
      if (problem != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
        return;
      }
      _loadRoute();
    }
    if (_step < 2) setState(() => _step++);
  }

  void _goBack() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      context.pop();
    }
  }

  /// Itinéraire routier passant par tous les points ; rechargé seulement si
  /// les points ont changé. En cas d'échec, les heures et prix sont estimés
  /// (même calcul que le backend).
  Future<void> _loadRoute() async {
    final points = _points;
    final key = points.map((p) => '${p.lat},${p.lng}').join('|');
    if (key == _routeKey && _route != null) return;
    setState(() {
      _routeKey = key;
      _route = null;
      _isLoadingRoute = true;
      _priceOverrides.clear();
    });
    RouteResult? route;
    try {
      route = await _mapService.getRouteThrough(points).timeout(const Duration(seconds: 12));
    } catch (_) {
      route = null;
    }
    if (!mounted || key != _routeKey) return;
    setState(() {
      _route = route;
      _isLoadingRoute = false;
    });
  }

  Future<void> _publish() async {
    final vehicle = _vehicle;
    if (vehicle == null || _step1Problem != null) return;

    setState(() => _isPublishing = true);
    try {
      await TripRepository().create(
        vehicleId: vehicle.id,
        stops: _plannedStops,
        seatsTotal: _seats,
        vehicleType: vehicle.type,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (!mounted) return;
      context.go('/home');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trajet publié avec succès.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException
              ? e.message
              : 'Échec de la publication. Réessayez.'),
        ),
      );
    }
  }

  static const _stepTitles = ['Itinéraire', 'Arrêts & horaires', 'Récapitulatif'];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    if (user != null && !user.isApprovedDriver) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: BrandAppBar(title: 'Publier un trajet', onBack: () => context.pop()),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user_outlined, size: 36, color: AppColors.primary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Compte non vérifié',
                    style: AppTextStyles.title1.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Pour publier un trajet, vous devez d\'abord faire vérifier votre identité et renseigner les informations de votre véhicule.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  FojemButton.primary(
                    label: 'Faire vérifier mon compte',
                    prefixIcon: Icons.badge_outlined,
                    onPressed: () => context.push('/profile/identity'),
                  ),
                  const SizedBox(height: 12),
                  FojemButton.secondary(
                    label: 'Retour',
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(
        title: 'Publier un trajet',
        subtitle: '${_step + 1} sur 3 · ${_stepTitles[_step]}',
        onBack: _goBack,
        bottomHeight: 8,
        bottom: _StepProgress(step: _step, count: _stepTitles.length),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            if (!_isLoadingVehicle && _vehicle == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _NoVehicleBanner(onAddVehicle: _editVehicle),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: switch (_step) {
                  0 => _StepOne(
                      origin: _origin,
                      destination: _destination,
                      intermediate: _intermediate,
                      date: _date,
                      time: _time,
                      seats: _seats,
                      priceController: _priceController,
                      vehicle: _vehicle,
                      isLoadingVehicle: _isLoadingVehicle,
                      onPickOrigin: () => _pickPoint(_PointSlot.origin),
                      onPickDestination: () => _pickPoint(_PointSlot.destination),
                      onAddStop: () => _pickPoint(_PointSlot.intermediate),
                      onEditStop: (i) => _pickPoint(_PointSlot.intermediate, index: i),
                      onRemoveStop: (i) => setState(() => _intermediate.removeAt(i)),
                      onDate: _pickDate,
                      onTime: _pickTime,
                      onSeats: _pickSeats,
                      onPriceChanged: () => setState(() {}),
                      onAddVehicle: _editVehicle,
                      onChangeVehicle: _vehicles.length > 1 ? _selectVehicle : null,
                    ),
                  1 => _StepTwo(
                      stops: _plannedStops,
                      route: _route,
                      isLoadingRoute: _isLoadingRoute,
                      onEditPrice: _editStopPrice,
                      notesController: _notesController,
                    ),
                  _ => _StepThree(
                      stops: _plannedStops,
                      seats: _seats,
                      vehicle: _vehicle,
                      notes: _notesController.text.trim(),
                    ),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: _step < 2
                  ? FojemButton.primary(
                      label: 'Continuer',
                      suffixIcon: Icons.arrow_forward_rounded,
                      onPressed: _step == 1 && _isLoadingRoute ? null : _goNext,
                    )
                  : FojemButton.primary(
                      label: 'Publier le trajet',
                      prefixIcon: Icons.send_rounded,
                      isLoading: _isPublishing,
                      onPressed: _isPublishing ? null : _publish,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPoint(_PointSlot slot, {int? index}) async {
    final current = switch (slot) {
      _PointSlot.origin => _origin,
      _PointSlot.destination => _destination,
      _PointSlot.intermediate => index != null ? _intermediate[index] : null,
    };
    final picked = await Navigator.push<GeoLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: switch (slot) {
            _PointSlot.origin => 'Point de départ',
            _PointSlot.destination => 'Point d’arrivée',
            _PointSlot.intermediate => 'Arrêt sur la route',
          },
          initial: current,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      switch (slot) {
        case _PointSlot.origin:
          _origin = picked;
        case _PointSlot.destination:
          _destination = picked;
        case _PointSlot.intermediate:
          if (index != null) {
            _intermediate[index] = picked;
          } else {
            _intermediate.add(picked);
          }
      }
      if (_origin != null) {
        final ordered = orderAlongRoute(_origin!, _intermediate);
        _intermediate
          ..clear()
          ..addAll(ordered);
      }
    });
  }

  Future<void> _editStopPrice(int index) async {
    final stops = _plannedStops;
    final stop = stops[index];
    final min = stops[index - 1].priceFromOrigin;
    final max = stops[index + 1].priceFromOrigin;
    final controller = TextEditingController(text: stop.priceFromOrigin.round().toString());
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Prix ${stops.first.location.shortLabel} → ${stop.location.shortLabel}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Entre ${formatFcfa(min)} et ${formatFcfa(max)} par place. '
              'Les passagers qui montent ou descendent ici paient la différence entre deux arrêts.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            FojemTextField(
              controller: controller,
              hint: '${stop.priceFromOrigin.round()}',
              keyboardType: TextInputType.number,
              suffix: const Padding(
                padding: EdgeInsets.only(right: AppSpacing.md),
                child: Text('FCFA', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.replaceAll(' ', ''))),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    if (value < min || value > max) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Le prix doit être compris entre ${formatFcfa(min)} et ${formatFcfa(max)}.'),
      ));
      return;
    }
    setState(() => _priceOverrides[index] = value);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickSeats() async {
    final max = _vehicle?.totalSeats ?? 15;
    final picked = await showOptionSheet<int>(
      context,
      title: 'Places disponibles',
      selected: _seats,
      options: [for (var i = 1; i <= max; i++) (i, '$i place${i > 1 ? 's' : ''}')],
    );
    if (picked != null) setState(() => _seats = picked);
  }

  Future<void> _editVehicle() async {
    await context.push('/driver/vehicle');
    if (!mounted) return;
    await _loadVehicle();
  }
}

enum _PointSlot { origin, destination, intermediate }

// ─── Étape 1 : itinéraire ──────────────────────────────────────────────────

class _StepOne extends StatelessWidget {
  final GeoLocation? origin;
  final GeoLocation? destination;
  final List<GeoLocation> intermediate;
  final DateTime date;
  final TimeOfDay time;
  final int seats;
  final TextEditingController priceController;
  final Vehicle? vehicle;
  final bool isLoadingVehicle;
  final VoidCallback onPickOrigin;
  final VoidCallback onPickDestination;
  final VoidCallback onAddStop;
  final ValueChanged<int> onEditStop;
  final ValueChanged<int> onRemoveStop;
  final VoidCallback onDate;
  final VoidCallback onTime;
  final VoidCallback onSeats;
  final VoidCallback onPriceChanged;
  final VoidCallback onAddVehicle;
  final VoidCallback? onChangeVehicle;

  const _StepOne({
    required this.origin,
    required this.destination,
    required this.intermediate,
    required this.date,
    required this.time,
    required this.seats,
    required this.priceController,
    required this.vehicle,
    required this.isLoadingVehicle,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.onAddStop,
    required this.onEditStop,
    required this.onRemoveStop,
    required this.onDate,
    required this.onTime,
    required this.onSeats,
    required this.onPriceChanged,
    required this.onAddVehicle,
    required this.onChangeVehicle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Indiquez des points de rendez-vous précis (gare routière, station, rond-point) : '
          'vos passagers viendront vous y retrouver.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: AppColors.softCardDecoration,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              _PointRow(
                label: 'Départ',
                point: origin,
                placeholder: 'D’où partez-vous ?',
                icon: Icons.adjust_rounded,
                onTap: onPickOrigin,
              ),
              for (var i = 0; i < intermediate.length; i++) ...[
                const Divider(height: 1, color: AppColors.border),
                _PointRow(
                  label: 'Arrêt ${i + 1}',
                  point: intermediate[i],
                  placeholder: '',
                  icon: Icons.radio_button_checked_rounded,
                  onTap: () => onEditStop(i),
                  onRemove: () => onRemoveStop(i),
                ),
              ],
              const Divider(height: 1, color: AppColors.border),
              _PointRow(
                label: 'Arrivée',
                point: destination,
                placeholder: 'Où allez-vous ?',
                icon: Icons.location_on_rounded,
                onTap: onPickDestination,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: onAddStop,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_location_alt_outlined, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Ajouter un arrêt sur la route',
                      style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Chaque arrêt permet à des passagers de monter ou descendre en route.',
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        Text('Date', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        _FieldRow(
          icon: Icons.calendar_month_rounded,
          text: formatDayLabel(date),
          onTap: onDate,
        ),
        const SizedBox(height: 16),
        Text('Heure de départ', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        _FieldRow(
          icon: Icons.access_time_rounded,
          text: time.format(context),
          onTap: onTime,
        ),
        const SizedBox(height: 16),
        Text('Places disponibles', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        _FieldRow(
          icon: Icons.event_seat_rounded,
          text: '$seats place${seats > 1 ? 's' : ''}',
          onTap: onSeats,
        ),
        const SizedBox(height: 16),
        Text('Prix par place (trajet complet)', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        FojemTextField(
          controller: priceController,
          hint: '2000',
          keyboardType: TextInputType.number,
          onChanged: (_) => onPriceChanged(),
          suffix: const Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: Text('FCFA', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
        if (intermediate.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Le prix des tronçons entre arrêts est calculé à l’étape suivante.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 16),
        Text('Véhicule', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        if (isLoadingVehicle)
          const _FieldRow(icon: Icons.directions_car_outlined, text: 'Chargement…', onTap: null)
        else if (vehicle == null)
          _FieldRow(
            icon: Icons.directions_car_outlined,
            text: 'Ajouter mon véhicule',
            onTap: onAddVehicle,
          )
        else
          _VehicleSummaryCard(vehicle: vehicle!, onChange: onChangeVehicle),
      ],
    );
  }
}

/// Ligne « point de rendez-vous » : libellé court + adresse précise.
class _PointRow extends StatelessWidget {
  final String label;
  final GeoLocation? point;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _PointRow({
    required this.label,
    required this.point,
    required this.placeholder,
    required this.icon,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    point?.shortLabel ?? placeholder,
                    style: point == null
                        ? AppTextStyles.bodyLargeSemibold.copyWith(color: AppColors.textMuted)
                        : AppTextStyles.bodyLargeSemibold,
                  ),
                  if (point != null && point!.address != point!.shortLabel) ...[
                    const SizedBox(height: 2),
                    Text(
                      point!.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                tooltip: 'Retirer cet arrêt',
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ─── Étape 2 : arrêts & horaires ───────────────────────────────────────────

class _StepTwo extends StatelessWidget {
  final List<PlannedStop> stops;
  final RouteResult? route;
  final bool isLoadingRoute;
  final ValueChanged<int> onEditPrice;
  final TextEditingController notesController;

  const _StepTwo({
    required this.stops,
    required this.route,
    required this.isLoadingRoute,
    required this.onEditPrice,
    required this.notesController,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final last = stops.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoutePreview(stops: stops, route: route, isLoading: isLoadingRoute),
        const SizedBox(height: 10),
        if (isLoadingRoute)
          Text('Calcul de l’itinéraire…',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted))
        else if (route != null)
          Text(
            '${route!.distanceKm.round()} km · arrivée prévue à ${timeFormat.format(stops.last.scheduledAt)}',
            style: AppTextStyles.bodySemibold,
          )
        else
          Text(
            'Itinéraire routier indisponible : horaires et prix estimés à partir des distances. '
            'Vérifiez-les avant de publier.',
            style: AppTextStyles.caption.copyWith(color: AppColors.danger),
          ),
        const SizedBox(height: 16),
        Container(
          decoration: AppColors.softCardDecoration,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < stops.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(timeFormat.format(stops[i].scheduledAt),
                            style: AppTextStyles.bodySemibold),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stops[i].location.shortLabel, style: AppTextStyles.bodyLargeSemibold),
                            Text(
                              stops[i].location.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (i > 0)
                        InkWell(
                          onTap: i < last ? () => onEditPrice(i) : null,
                          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(formatFcfa(stops[i].priceFromOrigin),
                                        style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary)),
                                    if (i < last) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
                                    ],
                                  ],
                                ),
                                Text(
                                  i == last
                                      ? 'trajet complet'
                                      : stops[i].priceEdited
                                          ? 'depuis le départ · ajusté'
                                          : 'depuis le départ',
                                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (stops.length > 2) ...[
          const SizedBox(height: 6),
          Text(
            'Prix calculés au prorata de la distance. Touchez un prix pour l’ajuster.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 24),
        Text('Informations pour les passagers', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        FojemTextField(
          controller: notesController,
          hint: 'Repère pour vous trouver, bagages, préférences…',
          maxLines: 4,
        ),
      ],
    );
  }
}

/// Carte du tracé avec les points de rendez-vous numérotés.
class _RoutePreview extends StatelessWidget {
  final List<PlannedStop> stops;
  final RouteResult? route;
  final bool isLoading;

  const _RoutePreview({required this.stops, required this.route, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final points = [for (final s in stops) ll.LatLng(s.location.lat, s.location.lng)];
    final line = route != null && route!.polyline.length >= 2
        ? [for (final p in route!.polyline) ll.LatLng(p.lat, p.lng)]
        : points;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            FlutterMap(
              // Recrée la carte quand le tracé arrive, pour recadrer dessus.
              key: ValueKey('${route?.distanceKm}-${points.length}'),
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(line.length >= 2 ? line : points),
                  padding: const EdgeInsets.all(28),
                ),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'sn.fojem.chauffeur',
                ),
                PolylineLayer(polylines: [
                  Polyline(points: line, strokeWidth: 4, color: AppColors.primary),
                ]),
                MarkerLayer(markers: [
                  for (var i = 0; i < points.length; i++)
                    Marker(
                      point: points[i],
                      width: 26,
                      height: 26,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == 0 || i == points.length - 1 ? AppColors.primary : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: i == 0 || i == points.length - 1 ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                ]),
              ],
            ),
            if (isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66FFFFFF),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Étape 3 : récapitulatif ────────────────────────────────────────────────

class _StepThree extends StatelessWidget {
  final List<PlannedStop> stops;
  final int seats;
  final Vehicle? vehicle;
  final String notes;

  const _StepThree({
    required this.stops,
    required this.seats,
    required this.vehicle,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final first = stops.first;
    final last = stops.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: AppColors.softCardDecoration,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(first.location.shortLabel,
                          style: AppTextStyles.title1.copyWith(fontSize: 19))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.primary),
                  ),
                  Expanded(
                    child: Text(last.location.shortLabel,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.title1.copyWith(fontSize: 19)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final stop in stops)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${timeFormat.format(stop.scheduledAt)}  ·  ${stop.location.address}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 14),
              _SummaryRow(icon: Icons.calendar_month_rounded, text: formatDayLabel(first.scheduledAt)),
              const SizedBox(height: 10),
              _SummaryRow(
                  icon: Icons.event_seat_rounded, text: '$seats place${seats > 1 ? 's' : ''}'),
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.directions_car_outlined,
                text: vehicle == null ? 'Véhicule non défini' : '${vehicle!.brand} ${vehicle!.model}',
              ),
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.payments_outlined,
                text: '${formatFcfa(last.priceFromOrigin)} / place (trajet complet)',
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                Text('Informations passagers', style: AppTextStyles.bodySemibold),
                const SizedBox(height: 4),
                Text(notes, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── En-tête + indicateur d'étape ──────────────────────────────────────────

/// Progression des 3 étapes, en barre blanche sur le dégradé de l'en-tête.
class _StepProgress extends StatelessWidget {
  final int step;
  final int count;

  const _StepProgress({required this.step, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        widthFactor: (step + 1) / count,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.onPrimary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _VehicleSummaryCard extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback? onChange;

  const _VehicleSummaryCard({required this.vehicle, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.softCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions_car_filled_rounded,
                size: 22, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${vehicle.brand} ${vehicle.model}',
                    style: AppTextStyles.bodyLargeSemibold),
                const SizedBox(height: 2),
                Text(
                  '${vehicle.typeLabel} · ${vehicle.totalSeats} places · ${vehicle.plateNumber}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (onChange != null)
            TextButton(
              onPressed: onChange,
              child: Text('Changer',
                  style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary)),
            ),
        ],
      ),
    );
  }
}

Future<Vehicle?> _showVehicleSelector(
  BuildContext context, {
  required List<Vehicle> vehicles,
  required String? selectedId,
}) {
  return showModalBottomSheet<Vehicle>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VehicleSelectorSheet(vehicles: vehicles, selectedId: selectedId),
  );
}

class _VehicleSelectorSheet extends StatelessWidget {
  final List<Vehicle> vehicles;
  final String? selectedId;

  const _VehicleSelectorSheet({required this.vehicles, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: AppColors.modalDecoration,
          child: Column(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Text('Choisir un véhicule', style: AppTextStyles.title2),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: vehicles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final vehicle = vehicles[index];
                    final isSelected = vehicle.id == selectedId;
                    return InkWell(
                      onTap: () => Navigator.pop(context, vehicle),
                      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primarySurface : AppColors.surface,
                          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.directions_car_filled_rounded,
                              size: 22,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${vehicle.brand} ${vehicle.model}',
                                      style: AppTextStyles.bodyLargeSemibold),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${vehicle.typeLabel} · ${vehicle.totalSeats} places · ${vehicle.plateNumber}',
                                    style: AppTextStyles.caption
                                        .copyWith(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
            ],
          ),
        );
      },
    );
  }
}

class _NoVehicleBanner extends StatelessWidget {
  final VoidCallback onAddVehicle;

  const _NoVehicleBanner({required this.onAddVehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 22, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aucun véhicule enregistré',
                    style: AppTextStyles.bodySemibold.copyWith(color: AppColors.danger)),
                const SizedBox(height: 2),
                Text(
                  'Ajoutez votre véhicule pour pouvoir publier un trajet.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAddVehicle,
            child: Text('Ajouter',
                style: AppTextStyles.bodySemibold.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}


class _FieldRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  const _FieldRow({required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: AppTextStyles.bodyLarge.copyWith(fontSize: 15.5))),
            if (onTap != null)
              const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textPrimary),
          ],
        ),
      ),
    );
  }
}


class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SummaryRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Text(text, style: AppTextStyles.bodyLarge.copyWith(fontSize: 15)),
      ],
    );
  }
}
