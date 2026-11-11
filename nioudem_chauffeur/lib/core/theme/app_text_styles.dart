import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Typographie : une seule famille, Inter, très lisible en petite taille et
/// aux chiffres réguliers (heures, prix). La hiérarchie vient de la taille et
/// de la graisse, pas de polices différentes.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle _inter(double size, FontWeight weight, {Color? color, double? height, double? spacing}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
        height: height,
        letterSpacing: spacing,
      );

  /// Grand titre d'écran (« Où allez-vous ? »).
  static TextStyle get display => _inter(28, FontWeight.w800, height: 1.15, spacing: -0.6);

  static TextStyle get title1 => _inter(22, FontWeight.w700, height: 1.25, spacing: -0.4);

  static TextStyle get title2 => _inter(18, FontWeight.w700, height: 1.3, spacing: -0.2);

  static TextStyle get bodyLarge => _inter(16, FontWeight.w400, height: 1.5);

  static TextStyle get bodyLargeSemibold => _inter(16, FontWeight.w600, height: 1.4);

  static TextStyle get body => _inter(14, FontWeight.w400, height: 1.45);

  static TextStyle get bodySemibold => _inter(14, FontWeight.w600, height: 1.45);

  static TextStyle get caption => _inter(12, FontWeight.w500, color: AppColors.textSecondary, height: 1.4);

  static TextStyle get label => _inter(12, FontWeight.w600, height: 1.4, spacing: 0.2);

  static TextStyle get buttonLarge => _inter(16, FontWeight.w700, height: 1.2);

  static TextStyle get buttonSmall => _inter(14, FontWeight.w600, height: 1.2);

  /// Prix : bleu nuit et gras, comme le reste des chiffres importants.
  static TextStyle get price => _inter(18, FontWeight.w800, height: 1.2, spacing: -0.3);

  static TextStyle get priceLarge => _inter(24, FontWeight.w800, height: 1.2, spacing: -0.5);
}
