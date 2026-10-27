import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Bandeau de confiance ("Voyagez en toute sérénité") en bas de l'accueil
/// et de l'onglet Trajets : bouclier vert, titre, phrase d'appui.
class TrustBanner extends StatelessWidget {
  final String title;
  final String subtitle;

  const TrustBanner({
    super.key,
    this.title = 'Voyagez en toute sérénité',
    this.subtitle = 'Tous nos chauffeurs sont vérifiés par FOJËM.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded,
              size: 38, color: AppColors.seatBadge),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyLargeSemibold.copyWith(
                    color: const Color(0xFF3A3A38),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
