import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'glow.dart';

/// Bandeau de confiance (« Voyagez en toute sérénité ») en bas de l'accueil
/// et des résultats : panneau en verre, bouclier vert.
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
    return GlassPanel(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, size: 40, color: AppColors.success),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
