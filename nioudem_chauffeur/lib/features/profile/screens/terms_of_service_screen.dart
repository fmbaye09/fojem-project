import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/fojem_card.dart';
import 'legal_placeholder_banner.dart';

/// Conditions générales d'utilisation — contenu provisoire en attendant la
/// validation juridique. Rendu statique, structuré en sections simples.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const _sections = [
    (
      'Objet',
      'FOJËM Chauffeur permet aux conducteurs de proposer des trajets de covoiturage interurbain au Sénégal et de gérer les réservations des passagers. L\'utilisation de l\'application implique l\'acceptation des présentes conditions.',
    ),
    (
      'Inscription et vérification',
      'Le chauffeur s\'engage à fournir des informations exactes (identité, permis de conduire, véhicule) et à maintenir son profil à jour. FOJËM se réserve le droit de suspendre un compte en cas d\'information erronée ou de comportement contraire aux présentes conditions.',
    ),
    (
      'Publication de trajets',
      'Le chauffeur est seul responsable de l\'exactitude des trajets publiés (horaires, tarifs, places disponibles) et de la conduite du véhicule dans le respect du code de la route sénégalais.',
    ),
    (
      'Paiement',
      'Le règlement des courses s\'effectue actuellement en espèces directement entre le passager et le chauffeur. FOJËM ne s\'interpose pas dans cette transaction et n\'est pas responsable des litiges financiers entre utilisateurs.',
    ),
    (
      'Responsabilité',
      'FOJËM agit comme intermédiaire de mise en relation et ne saurait être tenu responsable des dommages survenus pendant un trajet, sous réserve des dispositions légales applicables.',
    ),
    (
      'Modification des conditions',
      'FOJËM peut être amené à modifier ces conditions. Les utilisateurs seront informés de toute mise à jour significative.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandAppBar(title: 'Conditions générales d\'utilisation', onBack: () => context.pop()),
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
