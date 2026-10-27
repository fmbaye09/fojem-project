import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/seat_selection_provider.dart';

/// Barre de réservation fixe en bas de l'écran.
///
/// Affiche : sélection courante + prix total + bouton de confirmation.
/// Reproduit fidèlement le design de la maquette : ombre supérieure,
/// layout textes à gauche / bouton vert à droite.
class ReservationBar extends StatelessWidget {
  final VoidCallback? onConfirm;

  const ReservationBar({super.key, this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Consumer<SeatSelectionProvider>(
      builder: (context, provider, _) {
        final hasSelection = provider.selectedSeat != null;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
              child: Row(
                children: [
                  // ── Infos de sélection ────────────────────────────────
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(
                          label: 'Votre sélection :',
                          value: provider.selectionLabel,
                          valueWeight: FontWeight.w600,
                        ),
                        const SizedBox(height: 3),
                        _InfoRow(
                          label: 'Prix total :',
                          value: hasSelection ? provider.formattedPrice : '—',
                          valueColor: AppColors.primary,
                          valueWeight: FontWeight.w700,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ── Bouton de confirmation ────────────────────────────
                  AnimatedOpacity(
                    opacity: hasSelection ? 1.0 : 0.45,
                    duration: const Duration(milliseconds: 250),
                    child: _ConfirmButton(
                      label: hasSelection
                          ? 'Confirmer – ${provider.formattedPrice}'
                          : 'Confirmer la place',
                      onTap: hasSelection ? onConfirm : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final FontWeight valueWeight;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueWeight = FontWeight.w400,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 12.5,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: valueWeight,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _ConfirmButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withOpacity(0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}
