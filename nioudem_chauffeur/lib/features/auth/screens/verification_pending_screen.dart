import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../models/app_user.dart';
import '../../../providers/app_provider.dart';

/// Premier écran d'un chauffeur dont le compte n'est pas encore `approved` :
/// un message, "Soumettre les infos" (formulaire unique `/profile/identity`)
/// et "Actualiser le statut". Rien d'autre.
class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() => _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void reassemble() {
    super.reassemble();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await context.read<AppProvider>().refreshUser();
    if (!mounted) return;
    setState(() => _isRefreshing = false);
    final status = context.read<AppProvider>().user?.driverStatus;
    if (status == DriverVerificationStatus.approved) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user;
    final isRejected = user?.isRejectedDriver ?? false;
    final isPendingReview = user?.isPendingReview ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 36,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                isRejected
                    ? 'Votre dossier a été refusé'
                    : isPendingReview
                        ? 'Dossier en cours de vérification'
                        : 'Activez votre profil chauffeur',
                style: AppTextStyles.title2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                isRejected
                    ? 'Certains documents ont été refusés. Mettez à jour les pièces concernées pour activer votre compte.'
                    : isPendingReview
                        ? 'Vos documents ont bien été soumis. Notre équipe examine votre dossier sous 24h ouvrées.'
                        : 'Pour activer pleinement votre compte, vous devez faire vérifier votre identité et renseigner les informations de votre véhicule.',
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FojemButton.primary(
                label: isPendingReview
                    ? 'Modifier / Consulter les documents'
                    : isRejected
                        ? 'Corriger mon dossier'
                        : 'Commencer la vérification',
                prefixIcon: Icons.upload_file_rounded,
                onPressed: () => context.push('/profile/identity'),
              ),
              const SizedBox(height: AppSpacing.sm),
              FojemButton.secondary(
                label: 'Actualiser le statut',
                prefixIcon: Icons.refresh_rounded,
                isLoading: _isRefreshing,
                onPressed: _isRefreshing ? null : _refresh,
              ),
              const SizedBox(height: AppSpacing.md),
              FojemButton.ghost(
                label: 'Ignorer pour l\'instant (Accéder à l\'app)',
                prefixIcon: Icons.arrow_forward_rounded,
                onPressed: () => context.go('/home'),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () async {
                  await context.read<AppProvider>().signOut();
                  if (context.mounted) context.go('/role-selection');
                },
                child: Text(
                  'Se déconnecter',
                  style: AppTextStyles.caption.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
