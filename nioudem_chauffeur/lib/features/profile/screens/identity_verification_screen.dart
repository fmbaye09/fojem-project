import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_text_field.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/option_sheet.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../models/app_user.dart';
import '../../../models/driver_document.dart';
import '../../../models/vehicle.dart';
import '../../../providers/app_provider.dart';
import '../../../services/driver_document_repository.dart';

/// Formulaire d'activation chauffeur (route `/profile/identity`) :
/// Découpé en 2 phases distinctes :
/// 1. Phase 1 : Vérification d'identité du chauffeur (Permis recto/verso + Selfie permis).
/// 2. Phase 2 : Enregistrement du premier véhicule (Champs véhicule + Carte grise + Photos véhicule + Selfie carte grise).
/// Le chauffeur peut aussi enregistrer son identité et ajouter un véhicule ultérieurement.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  final _repository = DriverDocumentRepository();

  int _step = 0; // 0: Chauffeur (Identité), 1: Véhicule

  static const _identityTypes = [
    DriverDocumentType.permisRecto,
    DriverDocumentType.permisVerso,
    DriverDocumentType.selfiePermis,
  ];

  static const _vehicleTypes = [
    DriverDocumentType.carteGrise,
    DriverDocumentType.vehiculeAvant,
    DriverDocumentType.vehiculeArriere,
    DriverDocumentType.vehiculeGauche,
    DriverDocumentType.vehiculeDroite,
    DriverDocumentType.selfieCarteGrise,
  ];

  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();
  VehicleType _type = VehicleType.septPlaces;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  Map<DriverDocumentType, DriverDocument> _documents = const {};

  /// Photos choisies dans ce formulaire, pas encore envoyées.
  final Map<DriverDocumentType, PickedImage> _picked = {};

  bool get _needsVehicle =>
      context.read<AppProvider>().user?.driverStatus != DriverVerificationStatus.approved;

  bool get _identityValid => _identityTypes.every(
        (t) => _picked.containsKey(t) || _documents.containsKey(t),
      );

  bool get _hasAnyIdentityPicked => _identityTypes.any(
        (t) => _picked.containsKey(t) || _documents.containsKey(t),
      );

  bool get _vehicleFieldsValid =>
      !_needsVehicle ||
      (_brandController.text.trim().isNotEmpty &&
          _modelController.text.trim().isNotEmpty &&
          _colorController.text.trim().isNotEmpty &&
          _plateController.text.trim().isNotEmpty);

  bool get _vehicleDocsValid =>
      !_needsVehicle ||
      _vehicleTypes.every(
        (t) => _picked.containsKey(t) || _documents.containsKey(t),
      );

  bool get _canSubmitFull =>
      _identityValid && _vehicleFieldsValid && _vehicleDocsValid && !_isSubmitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await _repository.fetch();
      if (!mounted) return;
      _documents = {for (final d in data.documents) d.type: d};
      _prefillVehicle(data.vehicle);
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e is ApiException
            ? e.message
            : 'Impossible de charger le formulaire. Réessayez.';
      });
    }
  }

  void _prefillVehicle(Map<String, String> v) {
    _brandController.text = v['brand'] ?? '';
    _modelController.text = v['model'] ?? '';
    _colorController.text = v['color'] ?? '';
    _plateController.text = v['plate_number'] ?? '';
    final seats = int.tryParse(v['seat_count'] ?? '');
    if (seats != null) {
      _type = VehicleType.values.firstWhere(
        (t) => t.passengerSeatCount == seats,
        orElse: () => VehicleType.septPlaces,
      );
    }
  }

  Future<void> _pickType() async {
    final chosen = await showOptionSheet<VehicleType>(
      context,
      title: 'Type de véhicule',
      options: [for (final t in VehicleType.values) (t, t.label)],
      selected: _type,
    );
    if (chosen != null) setState(() => _type = chosen);
  }

  Future<void> _pickPhoto(DriverDocumentType type) async {
    final picked = await pickImageWithSourceSheet(context, title: type.label);
    if (picked == null || !mounted) return;
    setState(() => _picked[type] = picked);
  }

  Future<void> _submit({bool identityOnly = false}) async {
    setState(() => _isSubmitting = true);
    final needsVehicle = !identityOnly && _needsVehicle;
    try {
      final relevantTypes = identityOnly ? _identityTypes : DriverDocumentType.values;
      final filesToSend = <DriverDocumentType, OnboardingFile>{
        for (final e in _picked.entries)
          if (relevantTypes.contains(e.key))
            e.key: OnboardingFile(bytes: e.value.bytes, filename: e.value.filename),
      };

      await _repository.submit(
        brand: needsVehicle ? _brandController.text.trim() : null,
        model: needsVehicle ? _modelController.text.trim() : null,
        color: needsVehicle ? _colorController.text.trim() : null,
        plateNumber: needsVehicle ? _plateController.text.trim() : null,
        seatCount: needsVehicle ? _type.passengerSeatCount : null,
        files: filesToSend,
      );
      if (!mounted) return;
      await context.read<AppProvider>().refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            identityOnly
                ? 'Identité enregistrée. Vous pourrez ajouter un véhicule à tout moment.'
                : 'Informations envoyées. Votre dossier est en cours de vérification.',
          ),
        ),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Échec de l’envoi. Réessayez.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsVehicle = _needsVehicle;
    final isStep0 = _step == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isStep0 ? 'Vérification d’identité' : 'Informations du véhicule'),
        leading: IconButton(
          onPressed: () {
            if (_step == 1) {
              setState(() => _step = 0);
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
            ? const _FormSkeleton()
            : _loadError != null
                ? _LoadError(message: _loadError!, onRetry: _load)
                : Column(
                    children: [
                      _PhaseStepBar(
                        currentStep: _step,
                        onStepTapped: (step) {
                          if (step == 0) {
                            setState(() => _step = 0);
                          } else if (_identityValid) {
                            setState(() => _step = 1);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Veuillez d\'abord compléter les documents d\'identité.'),
                              ),
                            );
                          }
                        },
                        step1Done: _identityValid,
                        step2Done: _vehicleFieldsValid && _vehicleDocsValid,
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            if (isStep0) ...[
                              const _SectionHeader(
                                icon: Icons.badge_outlined,
                                title: 'Phase 1 : Identité du chauffeur',
                                subtitle:
                                    'Photographiez votre permis de conduire (recto et verso) et prenez un selfie en tenant votre permis.',
                              ),
                              const SizedBox(height: 18),
                              for (final type in _identityTypes) ...[
                                _PhotoField(
                                  type: type,
                                  document: _documents[type],
                                  picked: _picked[type]?.bytes,
                                  onTap: _isSubmitting ? null : () => _pickPhoto(type),
                                ),
                                const SizedBox(height: 16),
                              ],
                              const SizedBox(height: 6),
                              const _TipCard(
                                message:
                                    'Photos nettes, bien éclairées, document entier visible. Formats acceptés : JPG ou PNG.',
                              ),
                            ] else ...[
                              const _SectionHeader(
                                icon: Icons.directions_car_outlined,
                                title: 'Phase 2 : Informations du véhicule',
                                subtitle:
                                    'Renseignez votre premier véhicule de transport. Vous pourrez en ajouter d’autres plus tard dans « Mes véhicules ».',
                              ),
                              const SizedBox(height: 18),
                              if (needsVehicle) ...[
                                _SelectField(
                                  label: 'Type de véhicule',
                                  value: _type.label,
                                  icon: Icons.directions_car_filled_outlined,
                                  onTap: _pickType,
                                ),
                                const SizedBox(height: 16),
                                FojemTextField(
                                  label: 'Marque',
                                  hint: 'Toyota',
                                  controller: _brandController,
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                FojemTextField(
                                  label: 'Modèle',
                                  hint: 'Avanza',
                                  controller: _modelController,
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                FojemTextField(
                                  label: 'Couleur',
                                  hint: 'Gris',
                                  controller: _colorController,
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                FojemTextField(
                                  label: 'Plaque d’immatriculation',
                                  hint: 'DK-1234-AB',
                                  controller: _plateController,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 20),
                              ],
                              Text(
                                'Documents et photos du véhicule',
                                style: AppTextStyles.title2.copyWith(fontSize: 16),
                              ),
                              const SizedBox(height: 12),
                              for (final type in _vehicleTypes) ...[
                                _PhotoField(
                                  type: type,
                                  document: _documents[type],
                                  picked: _picked[type]?.bytes,
                                  onTap: _isSubmitting ? null : () => _pickPhoto(type),
                                ),
                                const SizedBox(height: 16),
                              ],
                              const SizedBox(height: 6),
                              const _TipCard(
                                message:
                                    'Veillez à ce que la carte grise et les 4 faces de votre voiture soient clairement visibles.',
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isStep0) ...[
                              FojemButton.primary(
                                label: 'Continuer vers le véhicule',
                                suffixIcon: Icons.arrow_forward_rounded,
                                onPressed: _identityValid ? () => setState(() => _step = 1) : null,
                              ),
                              if (_hasAnyIdentityPicked) ...[
                                const SizedBox(height: 10),
                                FojemButton.secondary(
                                  label: 'Enregistrer & ajouter la voiture plus tard',
                                  isLoading: _isSubmitting,
                                  onPressed: _isSubmitting ? null : () => _submit(identityOnly: true),
                                ),
                              ],
                            ] else ...[
                              FojemButton.primary(
                                label: 'Soumettre mon dossier complet',
                                prefixIcon: Icons.check_circle_outline_rounded,
                                isLoading: _isSubmitting,
                                onPressed: _canSubmitFull ? () => _submit(identityOnly: false) : null,
                              ),
                              const SizedBox(height: 10),
                              FojemButton.secondary(
                                label: 'Retour à l’étape identité',
                                onPressed: _isSubmitting ? null : () => setState(() => _step = 0),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ─── Barre de progression des 2 phases ─────────────────────────────────────

class _PhaseStepBar extends StatelessWidget {
  final int currentStep;
  final ValueChanged<int> onStepTapped;
  final bool step1Done;
  final bool step2Done;

  const _PhaseStepBar({
    required this.currentStep,
    required this.onStepTapped,
    required this.step1Done,
    required this.step2Done,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StepTab(
              stepNumber: 1,
              title: 'Identité chauffeur',
              isActive: currentStep == 0,
              isDone: step1Done,
              onTap: () => onStepTapped(0),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
          ),
          Expanded(
            child: _StepTab(
              stepNumber: 2,
              title: 'Véhicule',
              isActive: currentStep == 1,
              isDone: step2Done,
              onTap: () => onStepTapped(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTab extends StatelessWidget {
  final int stepNumber;
  final String title;
  final bool isActive;
  final bool isDone;
  final VoidCallback onTap;

  const _StepTab({
    required this.stepNumber,
    required this.title,
    required this.isActive,
    required this.isDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? AppColors.primary
        : (isDone ? AppColors.success : AppColors.textSecondary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primarySurface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
              child: Center(
                child: isDone && !isActive
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '$stepNumber',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyLargeSemibold.copyWith(fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final String message;

  const _TipCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Champs (même gabarit que FojemTextField) ──────────────────────────────

class _FieldShell extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color borderColor;
  final Widget leading;
  final String text;
  final bool filled;
  final Widget trailing;
  final String? errorText;

  const _FieldShell({
    required this.label,
    required this.onTap,
    required this.leading,
    required this.text,
    required this.filled,
    required this.trailing,
    this.borderColor = AppColors.border,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodySemibold.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: filled ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 14, color: AppColors.danger),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  errorText!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SelectField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _SelectField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      label: label,
      onTap: onTap,
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      text: value,
      filled: true,
      trailing: const Icon(Icons.expand_more_rounded, size: 20, color: AppColors.textSecondary),
    );
  }
}

class _PhotoField extends StatelessWidget {
  final DriverDocumentType type;
  final DriverDocument? document;
  final Uint8List? picked;
  final VoidCallback? onTap;

  const _PhotoField({
    required this.type,
    required this.document,
    required this.picked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = document?.status;
    final isRejected = status == DriverDocumentStatus.rejected && picked == null;

    final String text;
    final bool filled;
    if (picked != null) {
      text = 'Photo prête à envoyer';
      filled = true;
    } else if (status == DriverDocumentStatus.approved) {
      text = 'Validé';
      filled = true;
    } else if (status == DriverDocumentStatus.pending) {
      text = 'Envoyé, en vérification';
      filled = true;
    } else if (isRejected) {
      text = 'Refusé : choisir une nouvelle photo';
      filled = false;
    } else {
      text = 'Ajouter une photo';
      filled = false;
    }

    final reason = document?.rejectionReason;
    final hasFile = picked != null ||
        status == DriverDocumentStatus.approved ||
        status == DriverDocumentStatus.pending;

    return _FieldShell(
      label: type.label,
      onTap: onTap,
      borderColor: isRejected ? AppColors.danger : AppColors.border,
      leading: picked != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(picked!, width: 32, height: 32, fit: BoxFit.cover),
            )
          : Icon(type.icon, size: 20, color: AppColors.textSecondary),
      text: text,
      filled: filled,
      errorText: isRejected && reason != null ? 'Motif du refus : $reason' : null,
      trailing: Icon(
        hasFile ? Icons.check_circle_rounded : Icons.photo_camera_outlined,
        size: 20,
        color: hasFile ? AppColors.success : AppColors.textSecondary,
      ),
    );
  }
}

// ─── États de chargement / erreur ──────────────────────────────────────────

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: const [
        SkeletonBox(width: double.infinity, height: 72, borderRadius: 14),
        SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 12),
        SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 12),
        SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 12),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 44, color: AppColors.danger),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: AppTextStyles.body, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          FojemButton.secondary(label: 'Réessayer', onPressed: onRetry),
        ],
      ),
    );
  }
}
