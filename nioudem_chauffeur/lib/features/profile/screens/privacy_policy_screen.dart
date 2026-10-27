import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/fojem_card.dart';
import 'legal_placeholder_banner.dart';

/// Politique de confidentialité — contenu provisoire en attendant la
/// validation juridique. Rendu statique, structuré en sections simples.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = [
    (
      'Données collectées',
      'Nom, numéro de téléphone, photo de profil, pièce d\'identité et permis de conduire (pour la vérification), informations sur le véhicule, position des trajets publiés, historique des courses et des évaluations.',
    ),
    (
      'Utilisation des données',
      'Ces données servent à faire fonctionner la mise en relation avec les passagers, à sécuriser la plateforme (vérification d\'identité) et à améliorer le service. Elles ne sont pas vendues à des tiers.',
    ),
    (
      'Partage avec les passagers',
      'Certaines informations (prénom, note moyenne, véhicule, plaque d\'immatriculation) sont visibles par les passagers pour leur permettre d\'identifier le chauffeur et le véhicule.',
    ),
    (
      'Conservation',
      'Les données sont conservées le temps nécessaire à la fourniture du service et aux obligations légales applicables au Sénégal.',
    ),
    (
      'Sécurité',
      'Les données sont hébergées sur une infrastructure sécurisée (Firebase) avec un accès restreint. Le mot de passe n\'existe pas dans ce modèle : l\'authentification se fait par code envoyé par SMS.',
    ),
    (
      'Vos droits',
      'Vous pouvez demander la consultation, la correction ou la suppression de vos données personnelles en contactant le support FOJËM.',
    ),
  ];

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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LegalPlaceholderBanner(),
              const SizedBox(height: AppSpacing.lg),
              for (final section in _sections) ...[
                FojemCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section.$1, style: AppTextStyles.title2),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        section.$2,
                        style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
