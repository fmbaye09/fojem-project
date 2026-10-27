import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/trip_stop.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// « Monte à … / Descend à … » d'une réservation : le chauffeur sait à quel
/// point de rendez-vous attendre le passager et où il le dépose.
class StopSegment extends StatelessWidget {
  final TripStop? boarding;
  final TripStop? alighting;

  const StopSegment({super.key, required this.boarding, required this.alighting});

  @override
  Widget build(BuildContext context) {
    if (boarding == null && alighting == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (boarding != null)
          _StopLine(icon: Icons.login_rounded, verb: 'Monte', stop: boarding!),
        if (boarding != null && alighting != null) const SizedBox(height: 6),
        if (alighting != null)
          _StopLine(icon: Icons.logout_rounded, verb: 'Descend', stop: alighting!),
      ],
    );
  }
}

class _StopLine extends StatelessWidget {
  final IconData icon;
  final String verb;
  final TripStop stop;

  const _StopLine({required this.icon, required this.verb, required this.stop});

  @override
  Widget build(BuildContext context) {
    final time = stop.scheduledAt != null ? ' · ${DateFormat('HH:mm').format(stop.scheduledAt!)}' : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$verb à ${stop.name}$time', style: AppTextStyles.bodySemibold),
              if (stop.address != null && stop.address!.isNotEmpty && stop.address != stop.name)
                Text(
                  stop.address!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
