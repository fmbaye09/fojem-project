import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glow.dart';
import '../providers/seat_selection_provider.dart';

/// Barre de réservation fixe en bas : sélection courante,
/// prix total et bouton de confirmation à dégradé.
class ReservationBar extends StatelessWidget {
  final VoidCallback? onConfirm;

  const ReservationBar({super.key, this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Consumer<SeatSelectionProvider>(
      builder: (context, provider, _) {
        final hasSelection = provider.hasSelection;
        return BottomActionBar(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasSelection ? provider.selectionLabel : 'Aucune place choisie',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          hasSelection ? provider.formattedPrice : '—',
                          style: AppTextStyles.priceLarge.copyWith(fontSize: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GlowButton(
                    label: 'Confirmer',
                    expanded: false,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                    onPressed: hasSelection ? onConfirm : null,
                  ),
                ],
              ),
        );
      },
    );
  }
}
