import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_card.dart';

class _Section {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});
}

const _sections = [
  _Section(
    title: '1. Objet',
    body:
        'FOJËM met en relation des chauffeurs proposant des trajets interurbains et des passagers souhaitant réserver une place. FOJËM agit comme intermédiaire technique et n\'est pas transporteur.',
  ),
  _Section(
    title: '2. Inscription et compte',
    body:
        'L\'utilisation de l\'application nécessite un numéro de téléphone valide et l\'acceptation des présentes conditions. Chaque utilisateur est responsable de l\'exactitude des informations fournies et de la confidentialité de son compte.',
  ),
  _Section(
    title: '3. Réservations',
    body:
        'La réservation d\'une place constitue un engagement entre le passager et le chauffeur. Les annulations et remboursements sont soumis aux règles indiquées dans l\'application au moment de la réservation.',
  ),
  _Section(
    title: '4. Comportement des utilisateurs',
    body:
        'Chaque utilisateur s\'engage à adopter un comportement respectueux et à fournir des informations exactes sur son trajet, son véhicule ou son identité. Tout abus peut entraîner une suspension du compte.',
  ),
  _Section(
    title: '5. Responsabilité',
    body:
        'FOJËM met tout en œuvre pour vérifier l\'identité des chauffeurs mais ne peut garantir la conduite de chacun. FOJËM ne saurait être tenu responsable des incidents survenant pendant le trajet, en dehors de son rôle d\'intermédiaire.',
  ),
  _Section(
    title: '6. Modification des conditions',
    body:
        'FOJËM peut faire évoluer les présentes conditions. Les utilisateurs seront informés de toute modification substantielle via l\'application.',
  ),
  _Section(
    title: '7. Contact',
    body:
        'Pour toute question relative aux présentes conditions, contactez-nous via la rubrique "Aide et support" de l\'application.',
  ),
];

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Conditions générales d\'utilisation'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ProvisionalBanner(),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Conditions générales d\'utilisation',
              style: AppTextStyles.title1,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Dernière mise à jour : à définir',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: AppSpacing.lg),
            FojemCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final section in _sections) ...[
                    Text(section.title, style: AppTextStyles.bodySemibold),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      section.body,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (section != _sections.last)
                      const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _ProvisionalBanner extends StatelessWidget {
  const _ProvisionalBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Version provisoire, en cours de validation juridique.',
              style: AppTextStyles.caption.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
