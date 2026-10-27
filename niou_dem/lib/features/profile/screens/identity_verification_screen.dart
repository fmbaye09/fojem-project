import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_text_field.dart';
import '../../../providers/app_provider.dart';
import '../../../services/identity_verification_repository.dart';

enum DocumentChoice {
  idCard,
  driverLicense,
}

/// Écran de vérification d'identité voyageur :
/// Le voyageur a le choix entre sa Pièce d'identité (CNI / Passeport)
/// ou son Permis de conduire sénégalais.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  final _repository = IdentityVerificationRepository();
  final _picker = ImagePicker();

  DocumentChoice _selectedChoice = DocumentChoice.idCard;
  final _docNumberController = TextEditingController();

  File? _frontPhoto;
  File? _backPhoto;

  bool _isLoading = true;
  bool _isSubmitting = false;
  IdentityStatusData? _statusData;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  @override
  void dispose() {
    _docNumberController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final data = await _repository.fetch();
      if (!mounted) return;
      setState(() {
        _statusData = data;
        _isLoading = false;
        if (data.documentType == 'driver_license') {
          _selectedChoice = DocumentChoice.driverLicense;
        } else {
          _selectedChoice = DocumentChoice.idCard;
        }
        if (data.documentNumber != null) {
          _docNumberController.text = data.documentNumber!;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage(bool isFront) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isFront ? 'Photo du Recto (face avant)' : 'Photo du Verso (face arrière)',
                style: AppTextStyles.title2,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primarySurface,
                  child: Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                ),
                title: Text('Prendre une photo', style: AppTextStyles.bodySemibold),
                subtitle: const Text('Utiliser l’appareil photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primarySurface,
                  child: Icon(Icons.photo_library_rounded, color: AppColors.primary),
                ),
                title: Text('Choisir dans la galerie', style: AppTextStyles.bodySemibold),
                subtitle: const Text('Sélectionner un fichier existant'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null || !mounted) return;
      setState(() {
        if (isFront) {
          _frontPhoto = File(picked.path);
        } else {
          _backPhoto = File(picked.path);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de charger l’image.')),
      );
    }
  }

  bool get _canSubmit =>
      _frontPhoto != null && !_isSubmitting;

  Future<void> _submit() async {
    if (_frontPhoto == null) return;

    setState(() => _isSubmitting = true);
    try {
      final docType = _selectedChoice == DocumentChoice.idCard ? 'id_card' : 'driver_license';
      final updatedUser = await _repository.submit(
        documentType: docType,
        documentNumber: _docNumberController.text.trim(),
        frontPhoto: _frontPhoto!,
        backPhoto: _backPhoto,
      );

      if (!mounted) return;
      context.read<AppProvider>().updateUser(updatedUser);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Documents envoyés avec succès ! Examen en cours.'),
        ),
      );

      await _fetchStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    final status = _statusData?.status ?? user?.identityStatus ?? 'none';
    final isApproved = status == 'approved' || user?.identityVerified == true;
    final isPending = status == 'pending';
    final isRejected = status == 'rejected';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Vérification d’identité'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // État courant si déjà soumis
                  if (isApproved) ...[
                    _buildApprovedCard(),
                    const SizedBox(height: AppSpacing.lg),
                  ] else if (isPending) ...[
                    _buildPendingCard(),
                    const SizedBox(height: AppSpacing.lg),
                  ] else if (isRejected) ...[
                    _buildRejectedCard(_statusData?.rejectionReason ?? user?.identityRejectionReason),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (!isApproved) ...[
                    Text(
                      'Certification du compte voyageur',
                      style: AppTextStyles.title2,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choisissez le document officiel avec lequel vous souhaitez faire vérifier votre compte : votre Pièce d’identité (CNI / Passeport) ou votre Permis de conduire.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Sélecteur de Document : CNI ou Permis
                    Row(
                      children: [
                        Expanded(
                          child: _DocumentChoiceCard(
                            title: 'Pièce d’identité',
                            subtitle: 'CNI / Passeport',
                            icon: Icons.badge_outlined,
                            isSelected: _selectedChoice == DocumentChoice.idCard,
                            onTap: isPending
                                ? null
                                : () => setState(() => _selectedChoice = DocumentChoice.idCard),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _DocumentChoiceCard(
                            title: 'Permis de conduire',
                            subtitle: 'Permis sénégalais',
                            icon: Icons.drive_eta_outlined,
                            isSelected: _selectedChoice == DocumentChoice.driverLicense,
                            onTap: isPending
                                ? null
                                : () => setState(() => _selectedChoice = DocumentChoice.driverLicense),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Numéro de document
                    FojemTextField(
                      controller: _docNumberController,
                      label: _selectedChoice == DocumentChoice.idCard
                          ? 'Numéro de CNI ou Passeport (optionnel)'
                          : 'Numéro de permis de conduire (optionnel)',
                      hint: _selectedChoice == DocumentChoice.idCard
                          ? 'Ex : 1 234 5678 9012'
                          : 'Ex : SN-1234567',
                      enabled: !isPending,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Tuile Photo RECTO
                    _PhotoUploadTile(
                      title: _selectedChoice == DocumentChoice.idCard
                          ? 'Photo Recto — Face avant de la CNI'
                          : 'Photo Recto — Face avant du permis',
                      subtitle: 'Document net, bien cadré et lisible',
                      file: _frontPhoto,
                      remoteUrl: _statusData?.frontUrl,
                      isRequired: true,
                      onTap: isPending ? null : () => _pickImage(true),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Tuile Photo VERSO
                    _PhotoUploadTile(
                      title: _selectedChoice == DocumentChoice.idCard
                          ? 'Photo Verso — Face arrière (recommandé)'
                          : 'Photo Verso — Face arrière du permis',
                      subtitle: 'Optionnel mais accélère la validation',
                      file: _backPhoto,
                      remoteUrl: _statusData?.backUrl,
                      isRequired: false,
                      onTap: isPending ? null : () => _pickImage(false),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    if (!isPending) ...[
                      FojemButton.primary(
                        label: isRejected ? 'Renvoyer pour vérification' : 'Soumettre pour vérification',
                        prefixIcon: Icons.verified_user_rounded,
                        isLoading: _isSubmitting,
                        onPressed: _canSubmit ? _submit : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],

                  // Carte conseils de validation
                  _buildTipsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildApprovedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Identité vérifiée et certifiée',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Votre profil voyageur bénéficie du badge officiel certifié visible par les chauffeurs partenaires.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dossier en cours d’examen',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vos documents ont bien été reçus. Notre équipe administrative valide généralement les dossiers sous 24h.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedCard(String? reason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Document rejeté',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason != null && reason.isNotEmpty
                      ? 'Motif : $reason'
                      : 'La photo envoyée n’était pas suffisamment nette ou lisible. Veuillez reprendre une photo claire.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Pourquoi certifier votre compte ?', style: AppTextStyles.bodySemibold),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Les chauffeurs acceptent en priorité les demandes des profils vérifiés.\n'
            '• Accès aux trajets réservés aux membres de confiance.\n'
            '• Vos documents restent strictement confidentiels et sécurisés.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;

  const _DocumentChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primarySurface : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  size: 24,
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoUploadTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final File? file;
  final String? remoteUrl;
  final bool isRequired;
  final VoidCallback? onTap;

  const _PhotoUploadTile({
    required this.title,
    required this.subtitle,
    required this.file,
    required this.remoteUrl,
    required this.isRequired,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = file != null;
    final hasRemote = !hasFile && remoteUrl != null && remoteUrl!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (hasFile || hasRemote) ? AppColors.success : AppColors.border,
            width: (hasFile || hasRemote) ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
                image: hasFile
                    ? DecorationImage(image: FileImage(file!), fit: BoxFit.cover)
                    : (hasRemote ? DecorationImage(image: NetworkImage(remoteUrl!), fit: BoxFit.cover) : null),
              ),
              child: !(hasFile || hasRemote)
                  ? const Icon(Icons.add_a_photo_rounded, color: AppColors.primary, size: 24)
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: AppTextStyles.bodySemibold),
                      ),
                      if (isRequired)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Requis',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasFile
                        ? 'Photo sélectionnée (appuyez pour modifier)'
                        : (hasRemote
                            ? 'Document déjà soumis'
                            : subtitle),
                    style: AppTextStyles.caption.copyWith(
                      color: (hasFile || hasRemote) ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              (hasFile || hasRemote) ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
              color: (hasFile || hasRemote) ? AppColors.success : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
