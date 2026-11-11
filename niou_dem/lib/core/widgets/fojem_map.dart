import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Fond de carte OpenStreetMap légèrement désaturé : les repères de
/// l'appli (départs, chauffeur, arrêts) ressortent sur une carte calme.
class FojemTileLayer extends StatelessWidget {
  const FojemTileLayer({super.key});

  static const _muted = ColorFilter.matrix(<double>[
    0.5669, 0.3934, 0.0397, 0, 6, //
    0.1169, 0.8434, 0.0397, 0, 6, //
    0.1169, 0.3934, 0.4897, 0, 6, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'sn.fojem.app',
      tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _muted, child: tile),
    );
  }
}

/// Position de l'utilisateur : point bleu nuit cerclé de blanc.
class MyPositionDot extends StatelessWidget {
  const MyPositionDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: AppColors.floatingShadow,
        ),
      ),
    );
  }
}

/// Repère d'un départ sur la carte : étiquette blanche à l'heure du départ.
class DeparturePin extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const DeparturePin({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: 'Départ à $label',
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.brand, width: 2),
              boxShadow: AppColors.floatingShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_car_rounded, size: 14, color: AppColors.ink),
                const SizedBox(width: 4),
                Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800, height: 1.1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
