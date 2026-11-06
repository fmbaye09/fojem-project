import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/countdown.dart';
import '../../models/booking.dart';
import '../../models/trip.dart';
import '../../models/trip_stop.dart';

/// Ce que le billet dit du temps, recalculé chaque seconde :
/// - avant le départ, compte à rebours jusqu'au rendez-vous ;
/// - chauffeur arrivé, compte à rebours de son attente (après, il peut
///   déclarer le passager absent) ;
/// - en route, heure estimée de passage puis d'arrivée.
TimeStatus? meetingStatus(Trip trip, Booking booking, DateTime now) {
  if (booking.status != BookingStatus.confirmed && booking.status != BookingStatus.pending) return null;
  if (trip.status != TripStatus.upcoming && trip.status != TripStatus.inProgress) return null;

  final time = DateFormat('HH:mm');
  // Les arrêts du trajet sont rechargés plus souvent que ceux du billet.
  TripStop? fresh(TripStop? stop) =>
      stop == null ? null : trip.stops.firstWhere((s) => s.id == stop.id, orElse: () => stop);
  final boarding = fresh(booking.boardingStop) ?? (trip.stops.isEmpty ? null : trip.stops.first);
  final alighting = fresh(booking.alightingStop);

  // Le chauffeur est au point de montée et décompte son attente.
  final waitUntil = boarding?.waitUntil;
  if (boarding != null && waitUntil != null && booking.status == BookingStatus.confirmed && !booking.isBoarded) {
    final left = waitUntil.difference(now);
    if (left > Duration.zero) {
      return (
        icon: Icons.hourglass_bottom_rounded,
        tone: TimeTone.urgent,
        title: 'Le chauffeur vous attend · encore ${formatCountdown(left)}',
        detail: 'À ${boarding.name}, jusqu’à ${time.format(waitUntil)}. Passé ce délai, il pourra vous '
            'déclarer absent. Présentez votre QR code.',
      );
    }
    return (
      icon: Icons.timer_off_rounded,
      tone: TimeTone.late,
      title: 'Délai d’attente dépassé',
      detail: 'Le chauffeur vous attendait à ${boarding.name} jusqu’à ${time.format(waitUntil)} : '
          'il peut maintenant vous déclarer absent. Appelez-le si vous arrivez.',
    );
  }

  if (trip.status == TripStatus.upcoming) {
    final at = boarding?.scheduledAt ?? trip.departureTime;
    final where = '${time.format(at)}${boarding != null ? ' · ${boarding.name}' : ''}';
    final left = at.difference(now);
    if (left > const Duration(hours: 24)) {
      return (
        icon: Icons.schedule_rounded,
        tone: TimeTone.calm,
        title: 'Rendez-vous à $where',
        detail: 'Le chauffeur n’a pas encore démarré le trajet.',
      );
    }
    if (left > Duration.zero) {
      final soon = left <= const Duration(minutes: 15);
      return (
        icon: soon ? Icons.directions_walk_rounded : Icons.schedule_rounded,
        tone: soon ? TimeTone.soon : TimeTone.calm,
        title: 'Rendez-vous dans ${formatCountdown(left)}',
        detail: soon
            ? 'À $where. Soyez-y à l’heure : le chauffeur n’attend que $kDriverWaitMinutes min.'
            : 'À $where. Le chauffeur n’a pas encore démarré le trajet.',
      );
    }
    return (
      icon: Icons.schedule_rounded,
      tone: TimeTone.soon,
      title: 'Le chauffeur n’est pas encore arrivé',
      detail: 'Rendez-vous prévu à $where. Vous serez prévenu dès son arrivée.',
    );
  }

  // En route : passage au point de montée, puis arrivée à la descente.
  final live = trip.live;
  final target = booking.isBoarded ? alighting : boarding;
  if (target == null) return null;
  final eta = live?.etas[target.id];
  final passedTarget = (live?.lastPassedStopPosition ?? 0) >= target.position;

  if (!booking.isBoarded && passedTarget) {
    return (
      icon: Icons.where_to_vote_rounded,
      tone: TimeTone.urgent,
      title: 'Le chauffeur est à votre point de rendez-vous',
      detail: '${target.name} · ${target.displayAddress}. Présentez votre QR code.',
    );
  }
  if (eta == null) {
    return (
      icon: Icons.sensors_off_rounded,
      tone: TimeTone.calm,
      title: booking.isBoarded ? 'En route vers ${target.name}' : 'Le chauffeur est en route',
      detail: 'Heure d’arrivée indisponible pour le moment.',
    );
  }

  // Une estimation : à la minute, pas à la seconde.
  final minutes = eta.difference(now).inMinutes;
  final inLabel = minutes <= 1 ? 'd’un instant à l’autre' : 'dans $minutes min';
  final soon = !booking.isBoarded && minutes <= 10;
  final delay = live?.delayMinutes ?? 0;
  final detailParts = [
    if (live?.isLiveEstimate == true)
      'Estimation d’après la position du chauffeur'
    else
      'Estimation d’après l’horaire prévu (position indisponible)',
    if (delay >= 5) 'environ $delay min de retard',
    if (soon) 'soyez au point de rendez-vous : il n’attend que $kDriverWaitMinutes min',
  ];
  return (
    icon: booking.isBoarded ? Icons.flag_rounded : Icons.directions_car_filled_rounded,
    tone: soon ? TimeTone.soon : TimeTone.calm,
    title: booking.isBoarded
        ? 'Arrivée à ${target.name} vers ${time.format(eta)} · $inLabel'
        : 'Le chauffeur arrive à ${target.name} vers ${time.format(eta)} · $inLabel',
    detail: detailParts.join(' · '),
  );
}
