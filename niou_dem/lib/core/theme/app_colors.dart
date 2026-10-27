import 'package:flutter/material.dart';

/// Palette « Glow Flow » (template fojem-glow-flow) : lagon jade → azur
/// profond, accent mangue (héritage orange de FOJËM), surfaces claires
/// légèrement bleutées pour le néomorphisme.
///
/// Les noms historiques (primary, surface, textPrimary…) sont conservés :
/// tous les écrans basculent sur la nouvelle palette sans changer d'API.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF00A58C); // jade
  static const Color primaryGlow = Color(0xFF008ACE); // azur (fin du dégradé)
  static const Color primaryLight = Color(0xFF4CC3AE);
  static const Color primarySurface = Color(0xFFD6EEEB);
  static const Color onPrimary = Color(0xFFF8FDFD);

  static const Color accent = Color(0xFFFC8731); // mangue
  static const Color accentLight = Color(0xFFFFE6D2);

  static const Color danger = Color(0xFFEA3C3F);
  static const Color dangerSurface = Color(0xFFFDE4E4);
  static const Color success = Color(0xFF3BB360);
  static const Color successSurface = Color(0xFFE0F4E7);
  static const Color amber = Color(0xFFE08A12);
  static const Color amberSurface = Color(0xFFFFF0D9);

  static const Color background = Color(0xFFE7F3F3);
  static const Color surface = Color(0xFFF1F8F9);

  static const Color textPrimary = Color(0xFF07232F);
  static const Color textSecondary = Color(0xFF5C737C);
  static const Color textMuted = Color(0xFF8FA3AA);

  /// Onglets inactifs de la barre du bas.
  static const Color navInactive = Color(0xFF5C737C);

  /// Pastille « places disponibles » et badge « vérifié ».
  static const Color seatBadge = success;

  static const Color border = Color(0xFFD3E1E3);
  static const Color borderStrong = Color(0xFFB7CBCF);
  static const Color muted = Color(0xFFDFEAEC);

  static const Color shimmerBase = Color(0xFFDCE9EB);
  static const Color shimmerHighlight = Color(0xFFEFF7F8);

  // ── Dégradés ────────────────────────────────────────────────────────────

  /// Boutons principaux, en-têtes, avatars.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment(-0.9, -1),
    end: Alignment(1, 0.9),
    colors: [primary, primaryGlow],
  );

  /// Écran de démarrage : jade → bleu pétrole → mangue.
  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF009F86), Color(0xFF007583), Color(0xFFF58028)],
    stops: [0, 0.55, 1.15],
  );

  /// Fond doux de l'onboarding et de la connexion.
  static const LinearGradient sunriseGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE8FAF5), Color(0xFFFFF3E4)],
  );

  // ── Ombres néomorphiques ────────────────────────────────────────────────

  static const Color neuLight = Color(0xF2FFFFFF);
  static const Color neuDark = Color(0x38577782);

  /// Surface en relief.
  static const List<BoxShadow> neuShadow = [
    BoxShadow(color: neuDark, offset: Offset(8, 8), blurRadius: 20),
    BoxShadow(color: neuLight, offset: Offset(-8, -8), blurRadius: 20),
  ];

  static const List<BoxShadow> neuShadowSm = [
    BoxShadow(color: neuDark, offset: Offset(4, 4), blurRadius: 10),
    BoxShadow(color: neuLight, offset: Offset(-4, -4), blurRadius: 10),
  ];

  /// Halo coloré sous les boutons à dégradé.
  static const List<BoxShadow> glowShadow = [
    BoxShadow(color: Color(0x99008ACE), offset: Offset(0, 12), blurRadius: 30, spreadRadius: -10),
  ];


  // ── Identité de l'app ───────────────────────────────────────────────────
  // Jetons qui distinguent l'app voyageur de l'app chauffeur ; les widgets
  // partagés ne lisent que ceux-ci.

  /// Fond des en-têtes de page.
  static const LinearGradient headerGradient = brandGradient;

  /// Boutons d'action principaux et leur halo.
  static const LinearGradient ctaGradient = brandGradient;
  static const List<BoxShadow> ctaShadow = glowShadow;

  /// Onglet actif de la barre du bas.
  static const Color navActive = primary;

  // ── Décorations historiques (désormais néomorphiques) ───────────────────

  static const BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.all(Radius.circular(22)),
    boxShadow: neuShadowSm,
  );

  /// Carte principale des listes : relief néomorphique complet.
  static const BoxDecoration softCardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.all(Radius.circular(24)),
    boxShadow: neuShadow,
  );

  static const BoxDecoration modalDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    boxShadow: [
      BoxShadow(color: Color(0x2607232F), blurRadius: 32, offset: Offset(0, -8)),
    ],
  );
}
