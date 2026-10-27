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
    title: '1. Données collectées',
    body:
        'Nous collectons les informations nécessaires au fonctionnement du service : nom, numéro de téléphone, photo de profil, informations de trajet et de réservation, ainsi que, pour les chauffeurs, les documents d\'identité et de véhicule requis pour la vérification.',
  ),
  _Section(
    title: '2. Utilisation des données',
    body:
        'Vos données sont utilisées pour créer et gérer votre compte, faciliter la mise en relation entre passagers et chauffeurs, assurer la sécurité de la plateforme et vous contacter en cas de besoin lié à un trajet.',
  ),
  _Section(
    title: '3. Partage des données',
    body:
        'Certaines informations (nom, photo, note, trajet) sont visibles par les autres utilisateurs afin de permettre la mise en relation. Vos données ne sont pas vendues à des tiers.',
  ),
  _Section(
    title: '4. Conservation',
    body:
        'Vos données sont conservées le temps nécessaire à la fourniture du service et à nos obligations légales. Vous pouvez demander la suppression de votre compte via le support.',
  ),
  _Section(
    title: '5. Sécurité',
    body:
        'Nous mettons en œuvre des mesures raisonnables pour protéger vos données contre l\'accès non autorisé, la perte ou la divulgation.',
  ),
  _Section(
    title: '6. Vos droits',
    body:
        'Vous pouvez à tout moment demander l\'accès, la correction ou la suppression de vos données personnelles en nous contactant via la rubrique "Aide et support".',
  ),
];

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Politique de confidentialité'),
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
              'Politique de confidentialité',
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
