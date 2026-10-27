import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Palette extraite par échantillonnage pixel des 11 maquettes de référence
  // (design/screens/) — remplace l'ancienne palette vert/ambre par le
  // système marine/orange observé sur les écrans fournis.
  static const Color primary = Color(0xFFEA671A); // orange CTA (mesuré ~#E5-EE 65-6B 15-22)
  static const Color primaryLight = Color(0xFFF08C4C);
  static const Color primarySurface = Color(0xFFFFF2DB); // pastille "en attente", cercles d'icône

  static const Color accent = Color(0xFFEA671A);
  static const Color accentLight = Color(0xFFFDE1C6); // bulle de chat reçue, cercles d'icône pêche

  static const Color danger = Color(0xFFBE4947);
  static const Color dangerSurface = Color(0xFFF7E8E7);
  static const Color success = Color(0xFF32963C);
  static const Color successSurface = Color(0xFFECF5EB);
  static const Color amber = Color(0xFFD97706);
  static const Color amberSurface = Color(0xFFFEF3C7);

  static const Color background = Color(0xFFFBF9F7);
  static const Color surface = Color(0xFFFFFFFF);

  // "Encre" marine — titres, icônes, bulles de chat envoyées. Remplace le
  // quasi-noir précédent : dans les maquettes, le texte de titre EST cette
  // teinte marine, pas un simple gris foncé.
  static const Color textPrimary = Color(0xFF0B2A47);
  static const Color textSecondary = Color(0xFF5B5B58);
  static const Color textMuted = Color(0xFFA0A09A);

  /// Icônes/libellés des onglets inactifs de la barre du bas (gris ardoise
  /// des maquettes, plus soutenu que textMuted).
  static const Color navInactive = Color(0xFF55585E);

  /// Pastille verte "Places disponibles" et badge "vérifié".
  static const Color seatBadge = Color(0xFF2E9A41);

  static const Color border = Color(0xFFE8E6E0);
  static const Color borderStrong = Color(0xFFC8C6C0);

  static const Color shimmerBase = Color(0xFFEDEBE6);
  static const Color shimmerHighlight = Color(0xFFF8F7F4);

  static BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF000000).withOpacity(0.06),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: const Color(0xFF000000).withOpacity(0.04),
        blurRadius: 1,
        offset: const Offset(0, 0),
      ),
    ],
  );

  /// Carte blanche des écrans voyageur : filet très clair + ombre diffuse,
  /// juste assez pour détacher la carte du fond crème.
  static final BoxDecoration softCardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: const Color(0xFFEFEDE8)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0D1B1B1B),
        blurRadius: 14,
        offset: Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration modalDecoration = BoxDecoration(
    color: surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF000000).withOpacity(0.12),
        blurRadius: 32,
        offset: const Offset(0, -8),
      ),
    ],
  );
}
