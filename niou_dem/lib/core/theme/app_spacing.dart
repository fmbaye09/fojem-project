import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: lg,
  );

  static const double minTouchTarget = 48.0;

  static const double borderRadiusSm = 6.0;

  /// Cartes et boutons pleine largeur des écrans voyageur : coins sobres,
  /// nettement moins arrondis que les pastilles (cf. maquettes).
  static const double borderRadiusCard = 10.0;
  static const double borderRadiusButton = 8.0;
  static const double borderRadiusMd = 12.0;
  static const double borderRadiusLg = 20.0;
  static const double borderRadiusFull = 9999.0;
}
