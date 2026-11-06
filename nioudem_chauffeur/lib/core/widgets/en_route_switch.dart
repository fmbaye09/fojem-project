import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// « Accepter des passagers en route » : une fois parti, des passagers
/// réservent un arrêt pas encore atteint, confirmés d'office pour que le
/// chauffeur n'ait rien à valider en roulant.
class EnRouteSwitch extends StatelessWidget {
  final bool value;

  /// null pendant l'enregistrement du changement.
  final ValueChanged<bool>? onChanged;

  const EnRouteSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.softCardDecoration,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.alt_route_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Accepter des passagers en route', style: AppTextStyles.bodySemibold),
                const SizedBox(height: 4),
                Text(
                  'Une fois parti, des passagers peuvent réserver un arrêt que vous n’avez pas encore atteint, '
                  'au moins 15 min avant votre passage. Leur réservation est confirmée d’office : rien à valider en roulant.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
        ],
      ),
    );
  }
}
