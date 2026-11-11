import 'package:flutter/material.dart';

/// Palette FOJËM Pro (app chauffeur), alignée sur son icône : le bleu de la
/// voiture pour ce qu'on doit toucher (bouton principal, élément choisi),
/// le bleu nuit du logo pour le texte et les icônes, des surfaces blanches
/// sur un fond gris clair. Même système que l'app voyageur (orange) : une
/// seule couleur vive, réservée à l'action, le reste neutre et contrasté.
///
/// Les noms historiques (primary, surface, textPrimary…) sont conservés :
/// tous les écrans basculent sur la nouvelle palette sans changer d'API.
class AppColors {
  AppColors._();

  // ── Marque ──────────────────────────────────────────────────────────────

  /// Bleu de l'icône FOJËM Pro, foncé juste assez pour que le texte blanc
  /// reste lisible (4,8:1) : bouton principal, élément choisi.
  static const Color brand = Color(0xFF1F6FE0);

  /// Texte et icônes posés sur [brand].
  static const Color onBrand = Colors.white;

  /// Fond bleuté très pâle : élément choisi, pastille de marque.
  static const Color brandSurface = Color(0xFFE6F0FD);

  /// Bleu lisible en texte sur fond clair (5,5:1).
  static const Color brandText = Color(0xFF1A63D6);

  /// Bleu nuit du logo : texte principal, icônes, liens, boutons sombres.
  static const Color ink = Color(0xFF072945);

  // ── Rôles historiques ───────────────────────────────────────────────────

  /// Couleur interactive des icônes, liens et contours actifs : le bleu
  /// nuit, comme le texte. La couleur vive reste à [brand].
  static const Color primary = ink;
  static const Color primaryGlow = Color(0xFF1B4B73);
  static const Color primaryLight = Color(0xFF5D7A93);
  static const Color primarySurface = Color(0xFFEAF0F5);
  static const Color onPrimary = Colors.white;

  /// Accent : l'orange de la marque FOJËM (alertes douces, nouveautés).
  static const Color accent = Color(0xFFF16C1B);
  static const Color accentLight = Color(0xFFFFEFE4);

  static const Color danger = Color(0xFFD92D20);
  static const Color dangerSurface = Color(0xFFFEECEB);
  static const Color success = Color(0xFF12805C);
  static const Color successSurface = Color(0xFFE6F6EF);
  static const Color amber = Color(0xFFB54708);
  static const Color amberSurface = Color(0xFFFFF4E5);

  /// Fond des écrans (gris très clair) et des cartes (blanc).
  static const Color background = Color(0xFFF3F5F7);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = ink;
  static const Color textSecondary = Color(0xFF52606D);
  static const Color textMuted = Color(0xFF6B7684);

  /// Onglets inactifs de la barre du bas.
  static const Color navInactive = Color(0xFF6B7684);

  /// Pastille « places disponibles » et badge « vérifié ».
  static const Color seatBadge = success;

  static const Color border = Color(0xFFE3E8ED);
  static const Color borderStrong = Color(0xFFCBD3DC);

  /// Remplissage des champs et des boutons secondaires.
  static const Color muted = Color(0xFFF0F2F5);

  static const Color shimmerBase = Color(0xFFE8ECF0);
  static const Color shimmerHighlight = Color(0xFFF6F8FA);

  // ── Dégradés (désormais unis) ───────────────────────────────────────────

  static const LinearGradient brandGradient = LinearGradient(colors: [ink, ink]);
  /// Écran de démarrage : bleu nuit du logo, texte blanc.
  static const LinearGradient splashGradient = LinearGradient(colors: [ink, ink]);
  static const LinearGradient sunriseGradient = LinearGradient(colors: [surface, surface]);

  // ── Ombres ──────────────────────────────────────────────────────────────

  static const Color neuLight = Color(0x00FFFFFF);
  static const Color neuDark = Color(0x14072945);

  static const List<BoxShadow> neuShadow = [
    BoxShadow(color: Color(0x0F072945), offset: Offset(0, 2), blurRadius: 8),
  ];

  static const List<BoxShadow> neuShadowSm = [
    BoxShadow(color: Color(0x0D072945), offset: Offset(0, 1), blurRadius: 3),
  ];

  /// Élément flottant au-dessus de la carte (feuille, boutons ronds).
  static const List<BoxShadow> floatingShadow = [
    BoxShadow(color: Color(0x24072945), offset: Offset(0, 6), blurRadius: 20),
  ];

  static const List<BoxShadow> glowShadow = [];

  // ── Identité de l'app ───────────────────────────────────────────────────

  /// Ancien fond des en-têtes : les en-têtes sont désormais clairs.
  static const LinearGradient headerGradient = LinearGradient(colors: [surface, surface]);

  /// Bouton d'action principal : bleu plein, texte blanc.
  static const LinearGradient ctaGradient = LinearGradient(colors: [brand, brand]);
  static const List<BoxShadow> ctaShadow = [];

  /// Onglet actif de la barre du bas.
  static const Color navActive = ink;

  // ── Décorations ─────────────────────────────────────────────────────────

  static const BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.all(Radius.circular(16)),
    border: Border.fromBorderSide(BorderSide(color: border)),
  );

  static const BoxDecoration softCardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.all(Radius.circular(20)),
    border: Border.fromBorderSide(BorderSide(color: border)),
  );

  static const BoxDecoration modalDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    boxShadow: [
      BoxShadow(color: Color(0x1F072945), blurRadius: 24, offset: Offset(0, -4)),
    ],
  );
}
