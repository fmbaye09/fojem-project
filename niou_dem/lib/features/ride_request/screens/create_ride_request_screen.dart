import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/geo/geo_location.dart';
import '../../../core/geo/senegal_city_coordinates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/city_selector.dart';
import '../../../core/widgets/date_selector.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/location_picker_screen.dart';
import '../../../providers/app_provider.dart';
import '../../../services/ride_request_repository.dart';

/// Demande de trajet publiée par un passager quand aucune offre existante ne
/// lui convient (sélection hybride Ville + affinage Carte/GPS).
class CreateRideRequestScreen extends StatefulWidget {
  final String? initialFrom;
  final String? initialTo;

  const CreateRideRequestScreen({super.key, this.initialFrom, this.initialTo});

  @override
  State<CreateRideRequestScreen> createState() => _CreateRideRequestScreenState();
}

class _CreateRideRequestScreenState extends State<CreateRideRequestScreen> {
  String? _departure;
  String? _arrival;
  GeoLocation? _customOrigin;
  GeoLocation? _customDestination;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _departure = widget.initialFrom;
    _arrival = widget.initialTo;
  }

  bool get _isValid => _departure != null && _arrival != null;

  Future<void> _refineOnMap({required bool isDeparture}) async {
    final city = isDeparture ? _departure : _arrival;
    final initial = isDeparture
        ? (_customOrigin ?? (city != null ? coordinatesForCity(city) : null))
        : (_customDestination ?? (city != null ? coordinatesForCity(city) : null));

    final picked = await Navigator.of(context).push<GeoLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: isDeparture ? 'Point de départ exact' : 'Point d\'arrivée exact',
          initial: initial,
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

  Future<void> _submit() async {
    final user = context.read<AppProvider>().user;
    if (!_isValid || user == null) return;

    setState(() => _isSubmitting = true);
    final baseOrigin = _customOrigin ?? coordinatesForCity(_departure!);
    final baseDest = _customDestination ?? coordinatesForCity(_arrival!);

    final origin = GeoLocation(
      lat: baseOrigin.lat,
      lng: baseOrigin.lng,
      address: _departure!,
    );
    final destination = GeoLocation(
      lat: baseDest.lat,
      lng: baseDest.lng,
      address: _arrival!,
    );

    await RideRequestRepository().create(
      passengerId: user.id,
      passengerName: user.name.isEmpty ? user.phoneNumber : user.name,
      origin: origin,
      destination: destination,
      desiredDateTime: DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Demande publiée ! Nous recherchons automatiquement les chauffeurs compatibles.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    context.go('/my-requests');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Publier une demande'),
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aucun trajet ne correspond ? Publiez votre demande — '
                    'notre moteur FOJËM Match calcule automatiquement la compatibilité avec les chauffeurs sur votre axe.',
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Itinéraire souhaité', style: AppTextStyles.title2),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.radio_button_checked, color: AppColors.primary),
                          title: Text(
                            _departure ?? 'Choisir la ville de départ',
                            style: _departure != null
                                ? AppTextStyles.bodyLargeSemibold
                                : AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted),
                          ),
                          subtitle: _customOrigin != null
                              ? Text(
                                  '📍 ${_customOrigin!.address}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                                )
                              : null,
                          trailing: IconButton(
                            tooltip: 'Affiner sur la carte / GPS',
                            onPressed: () => _refineOnMap(isDeparture: true),
                            icon: const Icon(Icons.map_outlined, color: AppColors.primary),
                          ),
                          onTap: () async {
                            final city = await showCitySelector(context, title: 'Ville de départ', excludeCity: _arrival);
                            if (city != null) {
                              setState(() {
                                _departure = city;
                                _customOrigin = null;
                              });
                            }
                          },
                        ),
                        const Divider(height: 1, indent: 52, color: AppColors.border),
                        ListTile(
                          leading: const Icon(Icons.location_on, color: AppColors.accent),
                          title: Text(
                            _arrival ?? 'Choisir la ville d\'arrivée',
                            style: _arrival != null
                                ? AppTextStyles.bodyLargeSemibold
                                : AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted),
                          ),
                          subtitle: _customDestination != null
                              ? Text(
                                  '📍 ${_customDestination!.address}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                                )
                              : null,
                          trailing: IconButton(
                            tooltip: 'Affiner sur la carte / GPS',
                            onPressed: () => _refineOnMap(isDeparture: false),
                            icon: const Icon(Icons.map_outlined, color: AppColors.primary),
                          ),
                          onTap: () async {
                            final city = await showCitySelector(context, title: 'Ville d\'arrivée', excludeCity: _departure);
                            if (city != null) {
                              setState(() {
                                _arrival = city;
                                _customDestination = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Date et heure souhaitées', style: AppTextStyles.title2),
                  const SizedBox(height: AppSpacing.md),
                  DateSelector(selectedDate: _date, onDateChanged: (d) => setState(() => _date = d)),
                  const SizedBox(height: AppSpacing.md),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _time);
                      if (picked != null) setState(() => _time = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_outlined, size: 20, color: AppColors.textSecondary),
                          const SizedBox(width: AppSpacing.md),
                          const Text('Heure souhaitée'),
                          const Spacer(),
                          Text(
                            '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                            style: AppTextStyles.bodyLargeSemibold,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FojemButton.primary(
              label: 'Publier la demande',
              onPressed: _isValid && !_isSubmitting ? _submit : null,
              isLoading: _isSubmitting,
            ),
          ),
        ],
      ),
    );
  }
}
