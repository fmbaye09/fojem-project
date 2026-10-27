import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../models/trip.dart';
import 'driver_avatar.dart';
import 'glow.dart';

enum TripCardLayout {
  /// Accueil : jour + heure de montée en pied de carte.
  route,

  /// Résultats : distance à pied des arrêts proposés en pied de carte.
  schedule,
}

/// Carte trajet « Glow Flow » (template fojem-glow-flow) : chauffeur et prix
/// en tête, bloc en creux « heure · arrêt → durée → heure · arrêt », puis
/// date (ou distance des arrêts) et places. Affiche le tronçon du passager
/// (arrêts proposés par la recherche), pas le trajet complet du chauffeur.
class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;
  final TripCardLayout layout;

  const TripCard({
    super.key,
    required this.trip,
    required this.onTap,
    this.layout = TripCardLayout.route,
  });

  @override
  Widget build(BuildContext context) {
    final seg = trip.segment();
    final boardAt = boardingTime(trip);
    final arriveAt = seg.alighting?.scheduledAt ?? trip.departureTime.add(trip.estimatedDuration);
    final duration = arriveAt.difference(boardAt);
    final time = DateFormat('HH:mm');
    final driver = trip.driver;
    final match = trip.match;

    return Semantics(
      button: true,
      label: '${seg.boarding?.name ?? trip.departure} vers ${seg.alighting?.name ?? trip.arrival}, '
          '${formatDayLabel(boardAt)} à ${time.format(boardAt)}, '
          '${formatFcfa(seg.pricePerSeat)}',
      child: NeuBox(
        onTap: onTap,
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (driver != null)
                  DriverAvatar(name: driver.name, photoUrl: driver.photoUrl, size: 40)
                else
                  const BrandAvatar(name: '?', size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver?.shortName ?? 'Chauffeur',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySemibold.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (driver != null)
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
                            const SizedBox(width: 3),
                            Text(
                              '${driver.rating.toStringAsFixed(1).replaceAll('.', ',')}'
                              '${driver.totalTrips > 0 ? ' · ${driver.totalTrips} trajets' : ''}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Price(amount: seg.pricePerSeat),
              ],
            ),
            const SizedBox(height: 14),
            NeuInset(
              radius: 18,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: _TimeAndPlace(time: time.format(boardAt), place: seg.boarding?.name ?? trip.departure),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.accent),
                      if (duration.inMinutes > 0)
                        Text(_durationLabel(duration),
                            style: AppTextStyles.caption.copyWith(fontSize: 10.5)),
                    ],
                  ),
                  Expanded(
                    child: _TimeAndPlace(
                      time: time.format(arriveAt),
                      place: seg.alighting?.name ?? trip.arrival,
                      end: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  layout == TripCardLayout.schedule && match != null
                      ? Icons.directions_walk_rounded
                      : Icons.schedule_rounded,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    layout == TripCardLayout.schedule && match != null
                        ? 'Montée ${formatDistanceFromYou(match.boardingDistanceM)} · '
                            'descente ${formatDistanceFromYou(match.alightingDistanceM)}'
                        : formatDayLabel(boardAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                ),
                GlowPill(
                  icon: Icons.groups_rounded,
                  label: '${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _durationLabel(Duration d) {
    if (d.inHours == 0) return '${d.inMinutes}min';
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h${m.toString().padLeft(2, '0')}';
  }
}

class _TimeAndPlace extends StatelessWidget {
  final String time;
  final String place;
  final bool end;

  const _TimeAndPlace({required this.time, required this.place, this.end = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(time, style: AppTextStyles.title2.copyWith(fontSize: 18)),
        Text(
          place,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: end ? TextAlign.right : TextAlign.left,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
}

class SeatCountBadge extends StatelessWidget {
  final int count;

  const SeatCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.seatBadge,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.label.copyWith(
          color: Colors.white,
          fontSize: 12,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}


class _Price extends StatelessWidget {
  final double amount;

  const _Price({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Text(
      formatFcfa(amount),
      maxLines: 1,
      style:
          AppTextStyles.priceLarge.copyWith(fontSize: 19, letterSpacing: -0.3),
    );
  }
}

/// "★ 4,8 (124)" : étoile verte, note en gras, nombre d'avis en gris.
class RatingLine extends StatelessWidget {
  final double rating;
  final int count;

  const RatingLine({super.key, required this.rating, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: AppColors.seatBadge),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1).replaceAll('.', ','),
          style: AppTextStyles.bodySemibold.copyWith(fontSize: 13.5, height: 1),
        ),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: AppTextStyles.caption.copyWith(height: 1),
          ),
        ],
      ],
    );
  }
}

/// Squelette de chargement aux proportions d'une [TripCard].
class TripCardSkeleton extends StatelessWidget {
  const TripCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(4),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.softCardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(130, 20),
                const SizedBox(height: 14),
                bar(110, 12),
                const SizedBox(height: 10),
                bar(120, 12),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.shimmerBase,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  bar(60, 12),
                ],
              ),
              const SizedBox(height: 18),
              bar(80, 18),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Aujourd'hui", "Demain", sinon "ven. 26 sept.".
String formatDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Aujourd’hui';
  if (diff == 1) return 'Demain';
  return DateFormat('EEE d MMM', 'fr_FR').format(date);
}

/// "2 000 FCFA".
String formatFcfa(num amount) {
  final digits = NumberFormat('#,##0', 'fr_FR').format(amount.round());
  return '${digits.replaceAll(RegExp(r'[\s  ]'), ' ')} FCFA';
}
