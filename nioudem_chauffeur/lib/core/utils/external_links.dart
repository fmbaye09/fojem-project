import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

/// Petits utilitaires pour les actions externes (téléphone, email, Play
/// Store) utilisées depuis le support et les paramètres. Centralisés ici
/// pour éviter de dupliquer la logique d'ouverture/erreur dans chaque écran.
class ExternalLinks {
  ExternalLinks._();

  // TODO: remplacer par le vrai numéro support FOJËM
  static const String supportPhone = '+221 33 000 00 00';
  static const String supportEmail = 'support@fojem.sn';

  /// Identifiant technique Android existant — ne pas modifier.
  static const String androidPackageId = 'com.example.niou_dem_chauffeur';

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.textPrimary),
    );
  }

  static Future<void> call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: supportPhone.replaceAll(' ', ''));
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      _showSnack(context, 'Impossible d\'ouvrir l\'application téléphone.');
    }
  }

  static Future<void> email(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: 'subject=${Uri.encodeComponent('Support FOJËM Chauffeur')}',
    );
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      _showSnack(context, 'Impossible d\'ouvrir une application email.');
    }
  }

  static void chatComingSoon(BuildContext context) {
    _showSnack(
      context,
      'Le chat support arrive bientôt — contactez-nous par téléphone ou email en attendant.',
    );
  }

  static Future<void> rateApp(BuildContext context) async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$androidPackageId',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _showSnack(context, 'L\'application n\'est pas encore publiée sur le Play Store.');
      }
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'L\'application n\'est pas encore publiée sur le Play Store.');
      }
    }
  }
}
