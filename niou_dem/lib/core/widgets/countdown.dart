import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Attente du chauffeur au point de rendez-vous (`TripStop::WAIT_MINUTES`
/// côté backend), rappelée dans les textes.
const kDriverWaitMinutes = 5;

/// Temps restant lisible : « 2 j », « 1 h 05 », « 12 min », puis à la
/// seconde (« 4:05 ») sous 10 min. Zéro une fois l'heure passée.
String formatCountdown(Duration remaining) {
  final d = remaining.isNegative ? Duration.zero : remaining;
  if (d.inHours >= 24) return '${d.inDays} j';
  if (d.inHours >= 1) return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  if (d.inMinutes >= 10) return '${d.inMinutes} min';
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Urgence d'un message horaire, du plus calme au délai dépassé.
enum TimeTone { calm, soon, urgent, late }

typedef TimeStatus = ({IconData icon, String title, String? detail, TimeTone tone});

/// Reconstruit [builder] chaque seconde avec l'heure courante : comptes à
/// rebours sans recharger l'écran.
class EverySecond extends StatefulWidget {
  final Widget Function(BuildContext context, DateTime now) builder;

  const EverySecond({super.key, required this.builder});

  @override
  State<EverySecond> createState() => _EverySecondState();
}

class _EverySecondState extends State<EverySecond> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

/// Carte d'un message horaire, colorée selon son urgence.
class TimeStatusCard extends StatelessWidget {
  final TimeStatus status;

  const TimeStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color accent, Color surface) = switch (status.tone) {
      TimeTone.calm => (AppColors.primary, AppColors.primarySurface),
      TimeTone.soon => (AppColors.amber, AppColors.amberSurface),
      TimeTone.urgent => (AppColors.accent, AppColors.accentLight),
      TimeTone.late => (AppColors.danger, AppColors.dangerSurface),
    };
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, color: accent, size: 26),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: AppTextStyles.bodyLargeSemibold.copyWith(
                    // Chiffres à chasse fixe : le décompte ne fait pas sauter la ligne.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (status.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(status.detail!, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
