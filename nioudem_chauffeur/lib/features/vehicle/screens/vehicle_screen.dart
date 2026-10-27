import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_card.dart';
import '../../../core/widgets/fojem_text_field.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/verification_dialog.dart';
import '../../../models/vehicle.dart';
import '../../../providers/app_provider.dart';
import '../../../services/vehicle_repository.dart';

/// "Mes véhicules" (route `/driver/vehicle`) : un chauffeur peut déclarer
/// **plusieurs véhicules**. Cet écran affiche la liste de ceux déjà
/// déclarés (lecture seule — un véhicule est immuable une fois créé côté
/// backend, voir `fojem_backend/README.md` section "Vehicules") et permet
/// d'en ajouter un nouveau via `POST /vehicles`, qui crée toujours une
/// nouvelle ligne (jamais de mise à jour).
class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  bool _isLoading = true;
  bool _showForm = false;
  List<Vehicle> _vehicles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final vehicles = await VehicleRepository().fetchAll();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _onCreated(Vehicle vehicle) {
    setState(() {
      _vehicles = [..._vehicles, vehicle];
      _showForm = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_showForm ? 'Ajouter un véhicule' : 'Mes véhicules'),
        leading: IconButton(
          onPressed: () {
            if (_showForm) {
              setState(() => _showForm = false);
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const _VehicleSkeleton()
            : _showForm
                ? _AddVehicleForm(onCreated: _onCreated)
                : _VehicleList(
                    vehicles: _vehicles,
                    onAdd: () {
                      final user = context.read<AppProvider>().user;
                      if (user?.isApprovedDriver != true) {
                        showVerificationRequiredDialog(context, action: 'ajouter un véhicule');
                        return;
                      }
                      setState(() => _showForm = true);
                    },
                  ),
      ),
    );
  }
}

// ─── Liste des véhicules déclarés ───────────────────────────────────────────

class _VehicleList extends StatelessWidget {
  final List<Vehicle> vehicles;
  final VoidCallback onAdd;

  const _VehicleList({required this.vehicles, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vehicles.isEmpty
                ? 'Déclarez votre véhicule pour pouvoir publier des trajets.'
                : 'Choisissez le véhicule à utiliser au moment de publier un trajet.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (vehicles.isEmpty)
            const _EmptyVehicles()
          else
            for (final vehicle in vehicles) ...[
              _VehicleCard(vehicle: vehicle),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 12),
          FojemButton.primary(
            label: 'Ajouter un véhicule',
            prefixIcon: Icons.add_rounded,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _EmptyVehicles extends StatelessWidget {
  const _EmptyVehicles();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppColors.softCardDecoration,
      child: Column(
        children: [
          const Icon(Icons.directions_car_outlined, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            'Aucun véhicule déclaré pour le moment.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySemibold.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Carte lecture seule — pas de bouton "modifier" : un véhicule est
/// immuable une fois enregistré côté backend (anti-fraude, voir
/// `fojem_backend/README.md`).
class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;

  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return FojemCard(
      hasShadow: false,
      backgroundColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      '${vehicle.typeLabel} · ${vehicle.totalSeats} places',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              _Tag(icon: Icons.pin_rounded, label: vehicle.plateNumber),
              const SizedBox(width: 8),
              _Tag(icon: Icons.palette_outlined, label: vehicle.color),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ces informations sont définitives une fois enregistrées.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Tag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ─── Formulaire d'ajout d'un nouveau véhicule ───────────────────────────────

class _AddVehicleForm extends StatefulWidget {
  final ValueChanged<Vehicle> onCreated;

  const _AddVehicleForm({required this.onCreated});

  @override
  State<_AddVehicleForm> createState() => _AddVehicleFormState();
}

class _AddVehicleFormState extends State<_AddVehicleForm> {
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();
  VehicleType _type = VehicleType.septPlaces;
  bool _isSaving = false;

  bool get _isValid =>
      _brandController.text.trim().isNotEmpty &&
      _modelController.text.trim().isNotEmpty &&
      _plateController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final driverId = context.read<AppProvider>().user?.id;
    if (driverId == null || !_isValid) return;
    setState(() => _isSaving = true);
    try {
      final vehicle = await VehicleRepository().create(
        driverId: driverId,
        type: _type,
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        color: _colorController.text.trim(),
        plateNumber: _plateController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Véhicule ajouté.')),
      );
      widget.onCreated(vehicle);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de l’enregistrement. Réessayez.')),
      );
    }
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Une fois enregistré, ce véhicule ne pourra plus être modifié : '
            'vérifiez bien les informations avant de valider.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Text('Type de véhicule', style: AppTextStyles.bodySemibold),
          const SizedBox(height: 10),
          _SeatPreviewCard(type: _type),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: VehicleType.values.map((t) {
              final selected = t == _type;
              return ChoiceChip(
                label: Text(t.label),
                selected: selected,
                onSelected: (_) => setState(() => _type = t),
                selectedColor: AppColors.primarySurface,
                labelStyle: AppTextStyles.body.copyWith(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                backgroundColor: AppColors.surface,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          FojemTextField(
            label: 'Marque',
            hint: 'Toyota',
            controller: _brandController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          FojemTextField(
            label: 'Modèle',
            hint: 'Avanza',
            controller: _modelController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          FojemTextField(
            label: 'Couleur',
            hint: 'Gris',
            controller: _colorController,
          ),
          const SizedBox(height: 14),
          FojemTextField(
            label: 'Plaque d’immatriculation',
            hint: 'DK-1234-AB',
            controller: _plateController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          FojemButton.primary(
            label: 'Enregistrer',
            prefixIcon: Icons.check_rounded,
            isLoading: _isSaving,
            onPressed: _isValid && !_isSaving ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// Aperçu du plan de sièges — décoratif, se met à jour avec le type
/// sélectionné. `SeatLayoutWidget` n'existe pas dans ce repository (vérifié) :
/// on affiche donc une grille simple dérivée de `VehicleType.passengerSeatCount`
/// plutôt qu'un vrai plan de cabine.
class _SeatPreviewCard extends StatelessWidget {
  final VehicleType type;

  const _SeatPreviewCard({required this.type});

  @override
  Widget build(BuildContext context) {
    final seatCount = type.passengerSeatCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppColors.softCardDecoration,
      child: Row(
        children: [
          Icon(Icons.directions_car_filled_rounded, size: 28, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label, style: AppTextStyles.bodyLargeSemibold),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(
                    seatCount,
                    (_) => const Icon(Icons.event_seat_rounded,
                        size: 18, color: AppColors.seatBadge),
                  ),
                ),
              ],
            ),
          ),
          Text('$seatCount places', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _VehicleSkeleton extends StatelessWidget {
  const _VehicleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 90),
          const SizedBox(height: 20),
          const SkeletonBox(width: 140, height: 16),
          const SizedBox(height: 10),
          const SkeletonBox(height: 56),
          const SizedBox(height: 14),
          const SkeletonBox(height: 56),
          const SizedBox(height: 14),
          const SkeletonBox(height: 56),
          const SizedBox(height: 14),
          const SkeletonBox(height: 56),
        ],
      ),
    );
  }
}
