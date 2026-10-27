import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 20);
  static const EdgeInsets cardPadding = EdgeInsets.all(18);
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: lg,
  );

  static const double minTouchTarget = 48.0;

  // Coins généreux du style « Glow Flow » (néomorphisme + verre).
  static const double borderRadiusSm = 12.0;
  static const double borderRadiusCard = 24.0;
  static const double borderRadiusButton = 16.0;
  static const double borderRadiusMd = 18.0;
  static const double borderRadiusLg = 28.0;
  static const double borderRadiusFull = 9999.0;
}
