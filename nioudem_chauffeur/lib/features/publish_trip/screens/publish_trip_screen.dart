import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/city_selector.dart';
import '../../../core/widgets/location_picker_screen.dart';
import '../../../core/widgets/option_sheet.dart';
import '../../../core/widgets/trip_card.dart' show formatDayLabel, formatFcfa;
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_text_field.dart';
import '../../../models/vehicle.dart';
import '../../../providers/app_provider.dart';
import '../../../services/trip_repository.dart';
import '../../../services/vehicle_repository.dart';

/// Publication de trajet chauffeur, en 3 étapes (design/screens/
/// fojem_publish_trip.png pour l'étape 1) : détails du trajet (avec sélection
/// hybride ville + point exact carte/GPS), points de passage & informations pour
/// les passagers, puis récapitulatif + publication.
class PublishTripScreen extends StatefulWidget {
  const PublishTripScreen({super.key});

  @override
  State<PublishTripScreen> createState() => _PublishTripScreenState();
}

class _PublishTripScreenState extends State<PublishTripScreen> {
  int _step = 0;

  // Étape 1
  String? _departure;
  String? _arrival;
  GeoLocation? _customOrigin;
  GeoLocation? _customDestination;
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 30);
  int _seats = 3;
  final _priceController = TextEditingController(text: '2000');
  List<Vehicle> _vehicles = const [];
  Vehicle? _vehicle;
  bool _isLoadingVehicle = true;

  // Étape 2
  final List<String> _waypoints = [];
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

  bool get _step1Valid =>
      _departure != null &&
      _arrival != null &&
      _departure != _arrival &&
      _vehicle != null &&
      (double.tryParse(_priceController.text.replaceAll(' ', '')) ?? 0) > 0;

  void _goNext() {
    if (_step == 0 && !_step1Valid) return;
    if (_step < 2) setState(() => _step++);
  }

  void _goBack() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      context.pop();
    }
  }

  Future<void> _publish() async {
    final driverId = context.read<AppProvider>().user?.id;
    final vehicle = _vehicle;
    if (driverId == null || vehicle == null || !_step1Valid) return;

    setState(() => _isPublishing = true);
    final departureTime = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final origin = _customOrigin ?? coordinatesForCity(_departure!);
    final destination = _customDestination ?? coordinatesForCity(_arrival!);
    final distanceKm = origin.distanceKm(destination);
    final estimatedMinutes = (distanceKm / 70 * 60).round().clamp(15, 600);
    final price = double.tryParse(_priceController.text.replaceAll(' ', '')) ?? 0;

    try {
      await TripRepository().create(
        driverId: driverId,
        vehicleId: vehicle.id,
        departure: _departure!,
        arrival: _arrival!,
        departureAddress: _customOrigin?.address.isNotEmpty == true
            ? _customOrigin!.address
            : _departure!,
        arrivalAddress: _customDestination?.address.isNotEmpty == true
            ? _customDestination!.address
            : _arrival!,
        origin: origin,
        destination: destination,
        waypoints: _waypoints.map(coordinatesForCity).toList(),
        departureTime: departureTime,
        estimatedDuration: Duration(minutes: estimatedMinutes),
        seatsTotal: _seats,
        pricePerSeat: price,
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

  static const _stepTitles = ['Détails du trajet', 'Points de passage', 'Récapitulatif'];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    if (user != null && !user.isApprovedDriver) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Publier un trajet'),
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          ),
        ),
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
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: _goBack),
            _StepIndicator(step: _step, title: _stepTitles[_step]),
            const SizedBox(height: 8),
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
                      departure: _departure,
                      arrival: _arrival,
                      customOrigin: _customOrigin,
                      customDestination: _customDestination,
                      date: _date,
                      time: _time,
                      seats: _seats,
                      maxSeats: _vehicle?.totalSeats ?? 15,
                      priceController: _priceController,
                      vehicle: _vehicle,
                      isLoadingVehicle: _isLoadingVehicle,
                      onDeparture: () => _pickCity(isDeparture: true),
                      onArrival: () => _pickCity(isDeparture: false),
                      onRefineOriginOnMap: () => _refineOnMap(isDeparture: true),
                      onRefineDestinationOnMap: () => _refineOnMap(isDeparture: false),
                      onDate: _pickDate,
                      onTime: _pickTime,
                      onSeats: _pickSeats,
                      onAddVehicle: _editVehicle,
                      onChangeVehicle: _vehicles.length > 1 ? _selectVehicle : null,
                    ),
                  1 => _StepTwo(
                      waypoints: _waypoints,
                      onAddWaypoint: _addWaypoint,
                      onRemoveWaypoint: (i) => setState(() => _waypoints.removeAt(i)),
                      notesController: _notesController,
                    ),
                  _ => _StepThree(
                      departure: _departure!,
                      arrival: _arrival!,
                      customOrigin: _customOrigin,
                      customDestination: _customDestination,
                      waypoints: _waypoints,
                      date: _date,
                      time: _time,
                      seats: _seats,
                      price: double.tryParse(_priceController.text.replaceAll(' ', '')) ?? 0,
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
                      onPressed: _step == 0 && !_step1Valid ? null : _goNext,
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

  Future<void> _pickCity({required bool isDeparture}) async {
    final city = await showCitySelector(
      context,
      title: isDeparture ? 'Ville de départ' : 'Ville d’arrivée',
      excludeCity: isDeparture ? _arrival : _departure,
    );
    if (city == null) return;
    setState(() {
      if (isDeparture) {
        _departure = city;
        _customOrigin = null;
      } else {
        _arrival = city;
        _customDestination = null;
      }
    });
  }

  Future<void> _refineOnMap({required bool isDeparture}) async {
    final city = isDeparture ? _departure : _arrival;
    final current = isDeparture
        ? (_customOrigin ?? (city != null ? coordinatesForCity(city) : null))
        : (_customDestination ?? (city != null ? coordinatesForCity(city) : null));
    final picked = await Navigator.push<GeoLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: isDeparture ? 'Point exact de départ' : 'Point exact d’arrivée',
          initial: current,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isDeparture) {
        _customOrigin = picked;
        _departure ??= picked.address.split(',').first.trim();
      } else {
        _customDestination = picked;
        _arrival ??= picked.address.split(',').first.trim();
      }
    });
  }

  Future<void> _addWaypoint() async {
    final exclude = [
      if (_departure != null) _departure!,
      if (_arrival != null) _arrival!,
      ..._waypoints,
    ];
    final city = await showCitySelector(
      context,
      title: 'Ajouter une étape',
      excludeCity: exclude.isEmpty ? null : exclude.first,
    );
    if (city == null || exclude.contains(city)) return;
    setState(() => _waypoints.add(city));
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

// ─── En-tête + indicateur d'étape ──────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onBack;

  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 24, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              'Publier un trajet',
              style: AppTextStyles.title2.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  final String title;

  const _StepIndicator({required this.step, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              _Dot(isActive: i == step, isDone: i < step),
              if (i < 2)
                Container(
                  width: 28,
                  height: 2,
                  color: i < step ? AppColors.primary : AppColors.border,
                ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text('${step + 1} sur 3',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(title, style: AppTextStyles.title2),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool isActive;
  final bool isDone;

  const _Dot({required this.isActive, required this.isDone});

  @override
  Widget build(BuildContext context) {
    final filled = isActive || isDone;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.primary : AppColors.surface,
        border: filled ? null : Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Center(
        child: isDone
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : Icon(Icons.circle,
                size: 8, color: filled ? Colors.white : AppColors.border),
      ),
    );
  }
}

// ─── Étape 1 : détails du trajet ───────────────────────────────────────────

class _StepOne extends StatelessWidget {
  final String? departure;
  final String? arrival;
  final GeoLocation? customOrigin;
  final GeoLocation? customDestination;
  final DateTime date;
  final TimeOfDay time;
  final int seats;
  final int maxSeats;
  final TextEditingController priceController;
  final Vehicle? vehicle;
  final bool isLoadingVehicle;
  final VoidCallback onDeparture;
  final VoidCallback onArrival;
  final VoidCallback onRefineOriginOnMap;
  final VoidCallback onRefineDestinationOnMap;
  final VoidCallback onDate;
  final VoidCallback onTime;
  final VoidCallback onSeats;
  final VoidCallback onAddVehicle;
  final VoidCallback? onChangeVehicle;

  const _StepOne({
    required this.departure,
    required this.arrival,
    required this.customOrigin,
    required this.customDestination,
    required this.date,
    required this.time,
    required this.seats,
    required this.maxSeats,
    required this.priceController,
    required this.vehicle,
    required this.isLoadingVehicle,
    required this.onDeparture,
    required this.onArrival,
    required this.onRefineOriginOnMap,
    required this.onRefineDestinationOnMap,
    required this.onDate,
    required this.onTime,
    required this.onSeats,
    required this.onAddVehicle,
    required this.onChangeVehicle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldCard(
          label: 'Départ',
          value: departure,
          subtitle: customOrigin?.address,
          placeholder: 'D’où partez-vous ?',
          icon: Icons.adjust_rounded,
          onTap: onDeparture,
          onMapTap: onRefineOriginOnMap,
        ),
        const SizedBox(height: 12),
        _FieldCard(
          label: 'Arrivée',
          value: arrival,
          subtitle: customDestination?.address,
          placeholder: 'Où allez-vous ?',
          icon: Icons.location_on_rounded,
          onTap: onArrival,
          onMapTap: onRefineDestinationOnMap,
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
        Text('Prix par place', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        FojemTextField(
          controller: priceController,
          hint: '2000',
          keyboardType: TextInputType.number,
          suffix: const Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: Text('FCFA', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
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
        border: Border.all(color: AppColors.danger.withOpacity(0.25)),
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

class _FieldCard extends StatelessWidget {
  final String label;
  final String? value;
  final String? subtitle;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onMapTap;

  const _FieldCard({
    required this.label,
    required this.value,
    this.subtitle,
    required this.placeholder,
    required this.icon,
    required this.onTap,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.softCardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppColors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        value ?? placeholder,
                        style: value == null
                            ? AppTextStyles.bodyLargeSemibold.copyWith(color: AppColors.textMuted)
                            : AppTextStyles.bodyLargeSemibold,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '📍 $subtitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textPrimary),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 6),
          InkWell(
            onTap: onMapTap,
            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      subtitle != null
                          ? 'Modifier le point exact sur la carte / GPS'
                          : 'Préciser le point exact sur la carte ou par GPS',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primary),
                ],
              ),
            ),
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

// ─── Étape 2 : points de passage & informations ────────────────────────────

class _StepTwo extends StatelessWidget {
  final List<String> waypoints;
  final VoidCallback onAddWaypoint;
  final ValueChanged<int> onRemoveWaypoint;
  final TextEditingController notesController;

  const _StepTwo({
    required this.waypoints,
    required this.onAddWaypoint,
    required this.onRemoveWaypoint,
    required this.notesController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Étapes intermédiaires', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 6),
        Text(
          'Les villes que vous traversez permettent au système de matching de vous proposer des passagers sur votre route.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < waypoints.length; i++) ...[
          Container(
            decoration: AppColors.softCardDecoration,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.alt_route_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(waypoints[i], style: AppTextStyles.bodyLargeSemibold)),
                InkWell(
                  onTap: () => onRemoveWaypoint(i),
                  child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
        InkWell(
          onTap: onAddWaypoint,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Text('Ajouter une étape',
                    style: AppTextStyles.bodySemibold.copyWith(color: AppColors.primary)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Informations pour les passagers', style: AppTextStyles.bodySemibold),
        const SizedBox(height: 8),
        FojemTextField(
          controller: notesController,
          hint: 'Point de rendez-vous précis, bagages, préférences…',
          maxLines: 4,
        ),
      ],
    );
  }
}

// ─── Étape 3 : récapitulatif ────────────────────────────────────────────────

class _StepThree extends StatelessWidget {
  final String departure;
  final String arrival;
  final GeoLocation? customOrigin;
  final GeoLocation? customDestination;
  final List<String> waypoints;
  final DateTime date;
  final TimeOfDay time;
  final int seats;
  final double price;
  final Vehicle? vehicle;
  final String notes;

  const _StepThree({
    required this.departure,
    required this.arrival,
    this.customOrigin,
    this.customDestination,
    required this.waypoints,
    required this.date,
    required this.time,
    required this.seats,
    required this.price,
    required this.vehicle,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
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
                  Expanded(child: Text(departure, style: AppTextStyles.title1.copyWith(fontSize: 19))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.primary),
                  ),
                  Expanded(
                    child: Text(arrival,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.title1.copyWith(fontSize: 19)),
                  ),
                ],
              ),
              if (customOrigin != null) ...[
                const SizedBox(height: 6),
                Text('Départ précis : ${customOrigin!.address}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
              if (customDestination != null) ...[
                const SizedBox(height: 4),
                Text('Arrivée précise : ${customDestination!.address}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
              if (waypoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Via ${waypoints.join(', ')}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 14),
              _SummaryRow(icon: Icons.calendar_month_rounded, text: formatDayLabel(date)),
              const SizedBox(height: 10),
              _SummaryRow(icon: Icons.access_time_rounded, text: time.format(context)),
              const SizedBox(height: 10),
              _SummaryRow(
                  icon: Icons.event_seat_rounded, text: '$seats place${seats > 1 ? 's' : ''}'),
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.directions_car_outlined,
                text: vehicle == null ? 'Véhicule non défini' : '${vehicle!.brand} ${vehicle!.model}',
              ),
              const SizedBox(height: 10),
              _SummaryRow(icon: Icons.payments_outlined, text: '${formatFcfa(price)} / place'),
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
