import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/countdown.dart';
import '../../models/booking.dart';
import '../../models/trip.dart';
import '../../models/trip_stop.dart';

/// Le passager monte à cet arrêt (sans arrêt connu : au départ).
bool boardsAt(Booking booking, TripStop stop) =>
    booking.boardingStop?.id == stop.id || (booking.boardingStop == null && stop.position == 0);

/// Ce que l'écran du trajet dit du temps au chauffeur, recalculé chaque
/// seconde :
/// - avant le départ, compte à rebours, puis retard ;
/// - arrivé à un point de rendez-vous où des passagers manquent, compte à
///   rebours de l'attente, après quoi il peut les déclarer absents.
TimeStatus? departureStatus(Trip trip, List<Booking> confirmed, DateTime now) {
  if (trip.status != TripStatus.upcoming && trip.status != TripStatus.inProgress) return null;
  final time = DateFormat('HH:mm');

  // Dernier arrêt atteint : y attend-il encore des passagers ?
  final reached = trip.stops.where((s) => s.waitUntil != null).toList();
  if (reached.isNotEmpty) {
    final stop = reached.last;
    final missing = confirmed.where((b) => !b.isBoarded && boardsAt(b, stop)).length;
    if (missing > 0) {
      final plural = missing > 1;
      final who = '$missing passager${plural ? 's' : ''}';
      final leftAt = stop.leftAt;
      if (leftAt != null) {
        // Reparti : trop tôt, il peut encore faire demi-tour ; sinon, l'absence reste à déclarer.
        return leftAt.isBefore(stop.waitUntil!)
            ? (
                icon: Icons.report_rounded,
                tone: TimeTone.late,
                title: 'Parti de ${stop.name} sans $who',
                detail: '${plural ? 'Ils avaient' : 'Il avait'} jusqu’à ${time.format(stop.waitUntil!)} pour vous rejoindre : '
                    'faites demi-tour si vous le pouvez. Sinon, ce sera un trajet manqué, sans pénalité pour ${plural ? 'eux' : 'lui'}.',
              )
            : (
                icon: Icons.person_off_rounded,
                tone: TimeTone.soon,
                title: '$who pas venu${plural ? 's' : ''} à ${stop.name}',
                detail: 'Vous avez attendu jusqu’à ${time.format(stop.waitUntil!)} : '
                    'déclarez-${plural ? 'les' : 'le'} absent${plural ? 's' : ''}, ou indiquez-le en terminant le trajet.',
              );
      }
      final left = stop.waitUntil!.difference(now);
      if (left > Duration.zero) {
        return (
          icon: Icons.hourglass_bottom_rounded,
          tone: TimeTone.urgent,
          title: 'Attente à ${stop.name} · encore ${formatCountdown(left)}',
          detail: '$missing passager${plural ? 's' : ''} pas encore à bord. Après ${time.format(stop.waitUntil!)}, '
              'vous pourrez ${plural ? 'les' : 'le'} déclarer absent${plural ? 's' : ''}.',
        );
      }
      return (
        icon: Icons.timer_off_rounded,
        tone: TimeTone.soon,
        title: 'Délai d’attente écoulé à ${stop.name}',
        detail: '$missing passager${plural ? 's' : ''} manquant${plural ? 's' : ''} : '
            'appelez-${plural ? 'les' : 'le'} ou déclarez-${plural ? 'les' : 'le'} absent${plural ? 's' : ''} pour repartir.',
      );
    }
  }

  if (trip.status != TripStatus.upcoming) return null;

  final at = trip.departureTime;
  final start = trip.stops.isEmpty ? null : trip.stops.first;
  final where = '${time.format(at)}${start != null ? ' · ${start.name}' : ''}';
  final left = at.difference(now);
  if (left > const Duration(hours: 24)) return null;

  if (left > Duration.zero) {
    return (
      icon: Icons.schedule_rounded,
      tone: left <= const Duration(minutes: 15) ? TimeTone.soon : TimeTone.calm,
      title: 'Départ dans ${formatCountdown(left)}',
      detail: left <= const Duration(hours: 1)
          ? 'À $where. Gardez cet écran ouvert au point de départ : votre position prouve votre arrivée.'
          : 'À $where.',
    );
  }

  final late = now.difference(at).inMinutes;
  final notThere = start != null && start.reachedAt == null;
  final startName = start?.name ?? 'départ';
  return (
    icon: notThere ? Icons.wrong_location_rounded : Icons.play_circle_outline_rounded,
    tone: late >= kDriverWaitMinutes && notThere ? TimeTone.late : TimeTone.soon,
    title: late < 1 ? 'C’est l’heure du départ' : 'Départ prévu à ${time.format(at)} · il y a $late min',
    detail: notThere
        ? 'Vos passagers vous attendent à $startName. Votre position n’y a pas encore été reçue : '
            'gardez cet écran ouvert en arrivant.'
        : confirmed.isEmpty
            ? 'Aucun passager confirmé pour l’instant.'
            : 'Démarrez le trajet dès que vos passagers sont à bord.',
  );
}
