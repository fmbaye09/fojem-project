import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../models/booking.dart';
import '../../../models/trip.dart';

/// Billet du passager : QR code et code d'embarquement tant qu'il n'est pas
/// monté. Une fois sa présence validée par le chauffeur, le billet se replie
/// pour laisser la place au suivi ; un bouton le rouvre au besoin (contrôle).
class TicketCard extends StatefulWidget {
  final Booking booking;
  final Trip trip;

  const TicketCard({super.key, required this.booking, required this.trip});

  @override
  State<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> {
  bool _showQr = false;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final isCompleted = booking.status == BookingStatus.completed;
    final isConfirmed = booking.status == BookingStatus.confirmed;
    final isBoarded = booking.isBoarded;
    final folded = isConfirmed && isBoarded && !_showQr;

    final Color primaryColor = isCompleted
        ? const Color(0xFF2E7D32)
        : (isBoarded
            ? const Color(0xFF2E7D32)
            : (isConfirmed ? AppColors.primary : const Color(0xFFF59E0B)));

    final Color bgColor = isCompleted
        ? const Color(0xFFE8F5E9)
        : (isBoarded
            ? const Color(0xFFE8F5E9)
            : (isConfirmed ? AppColors.primarySurface : const Color(0xFFFFFBEB)));

    final String titleText = isCompleted
        ? 'Trajet terminé avec succès'
        : (isBoarded
            ? 'Présence validée à bord'
            : (isConfirmed ? 'Billet & Code QR d\'embarquement' : 'Réservation en attente'));

    final IconData titleIcon = isCompleted
        ? Icons.task_alt_rounded
        : (isBoarded
            ? Icons.check_circle_rounded
            : (isConfirmed ? Icons.qr_code_2_rounded : Icons.hourglass_top_rounded));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // En-tête ticket
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(titleIcon, color: primaryColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titleText,
                    style: AppTextStyles.bodySemibold.copyWith(color: primaryColor),
                  ),
                ),
                StatusChip(
                  variant: (isCompleted || isBoarded)
                      ? StatusChipVariant.completed
                      : (isConfirmed ? StatusChipVariant.confirmed : StatusChipVariant.pending),
                ),
              ],
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, folded ? 14 : 20, 20, isConfirmed && isBoarded ? 6 : 20),
              child: Column(
                children: [
                  if (isCompleted) ...[
                    const Icon(Icons.check_circle_outline_rounded, size: 54, color: Color(0xFF2E7D32)),
                    const SizedBox(height: 12),
                    Text('Bon retour !', style: AppTextStyles.title2),
                    const SizedBox(height: 6),
                    Text(
                      'Votre voyage s\'est bien terminé. Nous espérons que vous avez passé un excellent trajet.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ] else if (folded) ...[
                    Text(
                      'Le chauffeur a validé votre présence. Bon voyage !',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        color: const Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else if (isConfirmed) ...[
                    _BoardingPass(booking: booking),
                  ] else ...[
                    const Icon(Icons.hourglass_top_rounded, size: 40, color: Color(0xFFD97706)),
                    const SizedBox(height: 12),
                    Text(
                      'En attente d\'acceptation',
                      style: AppTextStyles.bodyLargeSemibold,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      booking.proposesNewStop
                          ? 'Vous avez proposé de ${booking.proposedStop!.isBoarding ? 'monter' : 'descendre'} à '
                              '${booking.proposedStop!.name}. Le chauffeur décide d\'ajouter cet arrêt à son trajet ; '
                              's\'il accepte, votre billet et votre code QR d\'embarquement apparaîtront ici.'
                          : 'Le chauffeur a reçu votre demande. Dès qu\'il valide, votre billet et votre code QR d\'embarquement apparaîtront ici.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],

                  SizedBox(height: folded ? 12 : 16),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 12),

                  // Récapitulatif rapide
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _DetailItem(
                        label: 'Places',
                        value: '${booking.seatsBooked} place${booking.seatsBooked > 1 ? 's' : ''}',
                      ),
                      Container(height: 24, width: 1, color: AppColors.border),
                      // Réglé en espèces au chauffeur : pas encore « payé » avant le voyage.
                      _DetailItem(
                        label: 'Prix',
                        value: '${booking.totalPrice.toInt()} FCFA',
                      ),
                      Container(height: 24, width: 1, color: AppColors.border),
                      // L'heure où il monte, pas le départ du chauffeur plus tôt sur la route.
                      _DetailItem(
                        label: 'Montée',
                        value: DateFormat('HH:mm').format(booking.boardingStop?.scheduledAt ?? widget.trip.departureTime),
                      ),
                    ],
                  ),

                  // À bord, le billet n'est plus utile qu'en cas de contrôle.
                  if (isConfirmed && isBoarded) ...[
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () => setState(() => _showQr = !_showQr),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: Icon(_showQr ? Icons.expand_less_rounded : Icons.qr_code_2_rounded, size: 18),
                      label: Text(
                        _showQr ? 'Masquer mon billet' : 'Afficher mon billet',
                        style: AppTextStyles.bodySemibold.copyWith(fontSize: 13, color: AppColors.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// QR code et code d'embarquement à 4 chiffres.
class _BoardingPass extends StatelessWidget {
  final Booking booking;

  const _BoardingPass({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isBoarded = booking.isBoarded;
    return Column(
      children: [
        Container(
          width: 170,
          height: 170,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: QrImageView(
            data: 'FOJEM:${booking.id}:${booking.confirmationCode}',
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 14),

        // Code de confirmation en grand
        Text(
          'Code d\'embarquement',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            booking.confirmationCode.isNotEmpty
                ? booking.confirmationCode
                : (booking.id.length >= 8 ? booking.id.substring(0, 8).toUpperCase() : booking.id),
            style: AppTextStyles.display.copyWith(
              fontSize: 30,
              letterSpacing: 10,
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isBoarded
              ? 'Votre présence a été validée par le chauffeur.'
              : 'Présentez ce QR code au chauffeur, ou donnez-lui ce code à 4 chiffres s’il ne peut pas scanner.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            fontSize: 12.5,
            color: isBoarded ? const Color(0xFF2E7D32) : AppColors.textSecondary,
            fontWeight: isBoarded ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;

  const _DetailItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.bodySemibold.copyWith(fontSize: 13)),
      ],
    );
  }
}
