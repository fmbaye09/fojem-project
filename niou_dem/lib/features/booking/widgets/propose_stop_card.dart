import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/trip_card.dart' show formatFcfa;
import '../../../models/proposed_stop.dart';

/// Sous les arrêts du trajet : proposer un autre point de rendez-vous, ou
/// celui déjà proposé, avec ce qu'il coûte au chauffeur.
class ProposeStopCard extends StatelessWidget {
  final ProposedStop? proposal;
  final VoidCallback onPropose;
  final VoidCallback onClear;

  const ProposeStopCard({super.key, required this.proposal, required this.onPropose, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    if (p == null) {
      return InkWell(
        onTap: onPropose,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          ),
          child: Row(
            children: [
              const Icon(Icons.add_location_alt_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aucun arrêt ne vous convient ?', style: AppTextStyles.bodySemibold),
                    Text(
                      'Proposez un point de rendez-vous sur la route : le chauffeur décide de l’ajouter.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.add_location_alt_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.isBoarding ? 'Vous montez' : 'Vous descendez'} à ${p.name}',
                      style: AppTextStyles.bodySemibold,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      proposalSummary(p),
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onClear, child: const Text('Choisir un arrêt du trajet')),
          ),
        ],
      ),
    );
  }
}

/// « Passage vers 08:45 · environ 6 min de détour pour le chauffeur, qui doit accepter. »
String proposalSummary(ProposedStop p) {
  final parts = [
    if (p.scheduledAt != null) 'Passage vers ${DateFormat('HH:mm').format(p.scheduledAt!)}',
    p.detourMinutes <= 1 ? 'presque aucun détour pour le chauffeur' : 'environ ${p.detourMinutes} min de détour pour le chauffeur',
  ];
  final text = parts.join(' · ');
  return '${text[0].toUpperCase()}${text.substring(1)}, qui doit accepter ce nouvel arrêt.';
}

/// Montre l'estimation au passager avant qu'il retienne le point.
Future<bool> confirmProposal(BuildContext context, ProposedStop proposal, {required double segmentPrice}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(proposal.name, style: AppTextStyles.title2),
            if (proposal.address != null && proposal.address != proposal.name)
              Text(proposal.address!, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            Text(proposalSummary(proposal), style: AppTextStyles.body),
            const SizedBox(height: 6),
            Text(
              'Prix de votre trajet : ${formatFcfa(segmentPrice)} par place. Sans réponse ou en cas de refus, '
              'vous pourrez choisir un des arrêts du chauffeur.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(proposal.isBoarding ? 'Monter à ce point' : 'Descendre à ce point'),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed == true;
}
