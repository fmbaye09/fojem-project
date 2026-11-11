import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../models/trip.dart';
import 'driver_avatar.dart';
import 'glow.dart';

enum TripCardLayout {
  /// Accueil : jour du départ sous l'arrêt de montée.
  route,

  /// Résultats : distance à pied des arrêts proposés.
  schedule,
}

/// Carte trajet : itinéraire du passager à gauche (heure · arrêt de montée,
/// durée, heure · arrêt de descente), prix à droite, chauffeur et places en
/// pied de carte. Affiche le tronçon du passager (arrêts proposés par la
/// recherche), pas le trajet complet du chauffeur.
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
    final walking = layout == TripCardLayout.schedule && match != null;
    final from = seg.boarding?.name ?? trip.departure;
    final to = seg.alighting?.name ?? trip.arrival;

    return Semantics(
      button: true,
      label: '$from vers $to, ${formatDayLabel(boardAt)} à ${time.format(boardAt)}, '
          '${formatFcfa(seg.pricePerSeat)}, ${trip.availableSeats} place${trip.availableSeats > 1 ? 's' : ''}',
      excludeSemantics: true,
      child: NeuBox(
        onTap: onTap,
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (match != null && match.enRoute) ...[
              _EnRouteBadge(stop: from, eta: match.boardingEta),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RouteTimeline(
                    stops: [
                      RouteTimelineStop(
                        time: time.format(boardAt),
                        place: from,
                        hint: walking ? formatDistanceFromYou(match.boardingDistanceM) : formatDayLabel(boardAt),
                        hintIcon: walking ? Icons.directions_walk_rounded : null,
                      ),
                      RouteTimelineStop(
                        time: time.format(arriveAt),
                        place: to,
                        hint: walking ? formatDistanceFromYou(match.alightingDistanceM) : null,
                        hintIcon: walking ? Icons.directions_walk_rounded : null,
                      ),
                    ],
                    duration: duration.inMinutes > 0 ? formatTripDuration(duration) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatFcfa(seg.pricePerSeat), maxLines: 1, style: AppTextStyles.price),
                    Text('par place', style: AppTextStyles.caption),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                if (driver != null)
                  DriverAvatar(name: driver.name, photoUrl: driver.photoUrl, size: 32)
                else
                  const BrandAvatar(name: '?', size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: driver?.shortName ?? 'Chauffeur', style: AppTextStyles.bodySemibold),
                        if (driver != null)
                          TextSpan(
                            // Pas encore noté : « Nouveau » plutôt qu'un « 0,0 » qui fait fuir.
                            text: driver.rating > 0
                                ? '  ★ ${driver.rating.toStringAsFixed(1).replaceAll('.', ',')}'
                                : '  Nouveau',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _Seats(count: trip.availableSeats),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Places restantes : vert tant qu'il en reste, gris quand c'est complet.
class _Seats extends StatelessWidget {
  final int count;

  const _Seats({required this.count});

  @override
  Widget build(BuildContext context) {
    final full = count <= 0;
    final color = full ? AppColors.textSecondary : AppColors.success;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event_seat_rounded, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          full ? 'Complet' : '$count place${count > 1 ? 's' : ''}',
          style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Une étape de [RouteTimeline] : heure, lieu, précision facultative.
class RouteTimelineStop {
  final String time;
  final String place;
  final String? hint;
  final IconData? hintIcon;

  const RouteTimelineStop({required this.time, required this.place, this.hint, this.hintIcon});
}

/// Itinéraire vertical : heures à gauche, pastilles reliées par un trait,
/// lieux à droite ; la durée s'affiche entre les deux heures.
class RouteTimeline extends StatelessWidget {
  final List<RouteTimelineStop> stops;
  final String? duration;

  const RouteTimeline({super.key, required this.stops, this.duration});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stops.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 48,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stops[i].time, style: AppTextStyles.bodyLargeSemibold.copyWith(fontWeight: FontWeight.w800)),
                      if (i == 0 && duration != null && stops.length > 1) ...[
                        const Spacer(),
                        Text(duration!, style: AppTextStyles.caption.copyWith(fontSize: 11)),
                        const Spacer(),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      const SizedBox(height: 5),
                      _Dot(filled: i == stops.length - 1),
                      if (i < stops.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: AppColors.borderStrong,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < stops.length - 1 ? 14 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stops[i].place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLargeSemibold,
                        ),
                        if (stops[i].hint != null)
                          Row(
                            children: [
                              if (stops[i].hintIcon != null) ...[
                                Icon(stops[i].hintIcon, size: 14, color: AppColors.textSecondary),
                                const SizedBox(width: 3),
                              ],
                              Flexible(
                                child: Text(
                                  stops[i].hint!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool filled;

  const _Dot({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.ink : AppColors.surface,
        border: Border.all(color: AppColors.ink, width: 2.5),
      ),
    );
  }
}

/// Trajet déjà parti, réservable à un arrêt qu'il n'a pas encore atteint.
class _EnRouteBadge extends StatelessWidget {
  final String stop;
  final DateTime? eta;

  const _EnRouteBadge({required this.stop, required this.eta});

  @override
  Widget build(BuildContext context) {
    final when = eta == null ? '' : ' vers ${DateFormat('HH:mm').format(eta!)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.alt_route_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'En route · passe à $stop$when',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
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

/// "★ 4,8 (124)" : étoile, note en gras, nombre d'avis en gris.
class RatingLine extends StatelessWidget {
  final double rating;
  final int count;

  const RatingLine({super.key, required this.rating, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: AppColors.brand),
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
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.softCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              bar(44, 16),
              const SizedBox(width: 16),
              bar(140, 16),
              const Spacer(),
              bar(70, 18),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              bar(44, 16),
              const SizedBox(width: 16),
              bar(110, 16),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: AppColors.shimmerBase, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              bar(90, 12),
              const Spacer(),
              bar(60, 12),
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
