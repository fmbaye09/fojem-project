import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../models/booking.dart';

/// Avant de terminer le trajet : pour chaque passager confirmé jamais validé
/// à bord, le chauffeur dit s'il a voyagé. Renvoie les réservations « pas
/// venu » (null si le chauffeur renonce).
Future<List<String>?> showCompleteTripSheet(BuildContext context, List<Booking> notScanned) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => CompleteTripSheet(notScanned: notScanned),
  );
}

class CompleteTripSheet extends StatefulWidget {
  final List<Booking> notScanned;

  const CompleteTripSheet({super.key, required this.notScanned});

  @override
  State<CompleteTripSheet> createState() => _CompleteTripSheetState();
}

class _CompleteTripSheetState extends State<CompleteTripSheet> {
  /// Réponse du chauffeur : vrai = a voyagé, faux = pas venu.
  final Map<String, bool> _rode = {};

  bool get _allAnswered => widget.notScanned.every((b) => _rode.containsKey(b.id));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Terminer le trajet', style: AppTextStyles.title2),
            const SizedBox(height: 6),
            Text(
              widget.notScanned.length > 1
                  ? 'Ces passagers n’ont pas été validés à bord. Ont-ils voyagé avec vous ?'
                  : 'Ce passager n’a pas été validé à bord. A-t-il voyagé avec vous ?',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in widget.notScanned)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.passengerName.isEmpty ? 'Passager' : b.passengerName, style: AppTextStyles.bodySemibold),
                          if (b.boardingStop != null)
                            Text(
                              'Devait monter à ${b.boardingStop!.name}',
                              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('A voyagé'),
                                selected: _rode[b.id] == true,
                                onSelected: (_) => setState(() => _rode[b.id] = true),
                              ),
                              ChoiceChip(
                                label: const Text('Pas venu'),
                                selected: _rode[b.id] == false,
                                onSelected: (_) => setState(() => _rode[b.id] = false),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pas venu : absent si vous l’avez attendu jusqu’au bout à son arrêt, sinon trajet manqué, '
              'sans pénalité pour lui. Seuls les passagers qui ont voyagé sont comptés dans vos gains.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            FojemButton.primary(
              label: 'Terminer le trajet',
              onPressed: _allAnswered
                  ? () => Navigator.pop(context, [
                        for (final b in widget.notScanned)
                          if (_rode[b.id] == false) b.id,
                      ])
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
