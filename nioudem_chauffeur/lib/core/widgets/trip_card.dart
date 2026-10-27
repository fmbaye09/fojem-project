import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import '../../models/trip.dart';

enum TripCardLayout {
  /// Accueil : "Dakar → Thiès", jour + heure de départ, places.
  route,

  /// Trajets : "08:30 → 10:00" avec les villes dessous, durée, places.
  schedule,
}

/// Carte trajet des maquettes Accueil et Trajets : infos du trajet à gauche,
/// chauffeur (photo, nom, note) et prix à droite. Toute la carte est
/// cliquable ; le détail du trajet porte la réservation.
///
/// Sur les écrans étroits (≈ 360 dp), le bloc chauffeur/prix passe sous les
/// infos du trajet plutôt que d'écraser les textes.
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

  static const _padding = EdgeInsets.fromLTRB(14, 16, 14, 16);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${trip.departure} vers ${trip.arrival}, '
          '${formatDayLabel(trip.departureTime)} à '
          '${DateFormat('HH:mm').format(trip.departureTime)}, '
          '${formatFcfa(trip.pricePerSeat)}',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
          child: Ink(
            decoration: AppColors.softCardDecoration,
            padding: _padding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 320;
                // Largeur restante à gauche du bloc chauffeur (avatar + nom ≈ 168).
                final infoWidth =
                    stacked ? constraints.maxWidth : constraints.maxWidth - 168;
                final shortSeats = infoWidth < 172;
                final info = layout == TripCardLayout.route
                    ? _RouteInfo(trip: trip, shortSeats: shortSeats)
                    : _ScheduleInfo(trip: trip, shortSeats: shortSeats);
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      info,
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: _DriverSummary(
                                  trip: trip, maxNameWidth: 200)),
                          const SizedBox(width: 12),
                          _Price(amount: trip.pricePerSeat),
                        ],
                      ),
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 158),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _DriverSummary(trip: trip, maxNameWidth: 108),
                            const SizedBox(height: 12),
                            _Price(amount: trip.pricePerSeat),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

final TextStyle _routeTitle = AppTextStyles.title1.copyWith(
  fontSize: 19,
  fontWeight: FontWeight.w700,
  height: 1.15,
  letterSpacing: -0.2,
);

final TextStyle _metaStyle = AppTextStyles.body.copyWith(
  fontSize: 13.5,
  color: AppColors.textSecondary,
  height: 1.25,
);

class _RouteInfo extends StatelessWidget {
  final Trip trip;
  final bool shortSeats;

  const _RouteInfo({required this.trip, required this.shortSeats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(trip.departure, style: _routeTitle),
              const _RouteArrow(),
              Text(trip.arrival, style: _routeTitle),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MetaLine(
          icon: Icons.schedule_rounded,
          text: '${formatDayLabel(trip.departureTime)} • '
              '${DateFormat('HH:mm').format(trip.departureTime)}',
        ),
        const SizedBox(height: 8),
        _SeatsLine(seats: trip.availableSeats, short: shortSeats),
      ],
    );
  }
}

class _ScheduleInfo extends StatelessWidget {
  final Trip trip;
  final bool shortSeats;

  const _ScheduleInfo({required this.trip, required this.shortSeats});

  @override
  Widget build(BuildContext context) {
    final arrivalTime = trip.departureTime.add(trip.estimatedDuration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimeAndCity(
                time: DateFormat('HH:mm').format(trip.departureTime),
                city: trip.departure,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: _RouteArrow(),
              ),
              _TimeAndCity(
                time: DateFormat('HH:mm').format(arrivalTime),
                city: trip.arrival,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MetaLine(
          icon: Icons.schedule_rounded,
          text: 'Durée estimée ${trip.durationLabel}',
        ),
        const SizedBox(height: 8),
        _SeatsLine(seats: trip.availableSeats, short: shortSeats),
      ],
    );
  }
}

class _TimeAndCity extends StatelessWidget {
  final String time;
  final String city;

  const _TimeAndCity({required this.time, required this.city});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(time, style: _routeTitle),
        const SizedBox(height: 2),
        Text(
          city,
          style: AppTextStyles.body
              .copyWith(color: AppColors.textPrimary, height: 1.2),
        ),
      ],
    );
  }
}

class _RouteArrow extends StatelessWidget {
  const _RouteArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child:
          Icon(Icons.arrow_forward_rounded, size: 20, color: AppColors.primary),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _metaStyle,
          ),
        ),
      ],
    );
  }
}

class _SeatsLine extends StatelessWidget {
  final int seats;
  final bool short;

  const _SeatsLine({required this.seats, required this.short});

  @override
  Widget build(BuildContext context) {
    // Libellé complet de la maquette quand la place le permet, sinon
    // "Places" seul : jamais de texte tronqué à côté de la pastille.
    return Row(
      children: [
        const Icon(Icons.directions_car_outlined,
            size: 16, color: AppColors.textMuted),
        const SizedBox(width: 7),
        Text(short ? 'Places' : 'Places disponibles',
            maxLines: 1, style: _metaStyle),
        const SizedBox(width: 8),
        SeatCountBadge(count: seats),
      ],
    );
  }
}

/// Pastille verte carrée avec le nombre de places restantes.
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

/// Le chauffeur d'un trajet n'est plus joint côté client (`Trip` n'expose
/// plus de champ `driver` — l'API Laravel ne renvoie ni ce champ ni de note/
/// photo pour l'instant). Ce bloc reste en no-op plutôt que de fabriquer un
/// profil chauffeur factice ; [TripCard] (non utilisé par l'app Chauffeur,
/// qui n'affiche jamais son propre profil sur ses propres cartes trajet)
/// s'affiche simplement sans ce bloc.
class _DriverSummary extends StatelessWidget {
  final Trip trip;
  final double maxNameWidth;

  const _DriverSummary({required this.trip, required this.maxNameWidth});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
      padding: TripCard._padding,
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
