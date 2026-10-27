import 'package:flutter/material.dart';
import '../../../models/trip.dart';
import '../../../models/vehicle.dart';
import '../models/seat.dart';

/// Sièges réels du trajet demandé : plan dérivé du véhicule du chauffeur,
/// prix réel du trajet et sièges déjà pris (`occupied_seats` renvoyé par le
/// backend). Le passager peut choisir plusieurs places, dans la limite des
/// places encore proposées par le chauffeur (`seatsAvailable`).
class SeatSelectionProvider extends ChangeNotifier {
  final VehicleType vehicleType;
  final double pricePerSeat;
  final int maxSelectable;
  final List<SeatState> _seats;

  /// [pricePerSeat] : prix du tronçon réservé (par défaut, trajet complet).
  factory SeatSelectionProvider.forTrip(Trip trip, {double? pricePerSeat}) {
    return SeatSelectionProvider._(
      vehicleType: trip.vehicleType,
      pricePerSeat: pricePerSeat ?? trip.pricePerSeat,
      maxSelectable: trip.availableSeats,
      occupiedSeatIds: trip.occupiedSeatIds.toSet(),
    );
  }

  SeatSelectionProvider._({
    required this.vehicleType,
    required this.pricePerSeat,
    required this.maxSelectable,
    required Set<String> occupiedSeatIds,
  }) : _seats = seatLayoutFor(vehicleType).map((c) {
          if (c.initialStatus == SeatStatus.driver) {
            return SeatState(config: c, status: SeatStatus.driver);
          }
          final status = occupiedSeatIds.contains(c.id) ? SeatStatus.occupied : SeatStatus.available;
          return SeatState(config: c, status: status);
        }).toList();

  List<SeatState> get seats => List.unmodifiable(_seats);

  List<SeatState> get selectedSeats => _seats.where((s) => s.isSelected).toList();

  Set<String> get selectedSeatIds => {for (final s in selectedSeats) s.config.id};

  bool get hasSelection => _seats.any((s) => s.isSelected);

  /// Places encore réservables : libres sur le plan, sans dépasser le
  /// nombre de places que le chauffeur propose encore.
  int get availableCount {
    final free = _seats.where((s) => s.isAvailable || s.isSelected).length;
    return free < maxSelectable ? free : maxSelectable;
  }

  int get totalPassengerSeats => _seats.where((s) => !s.isDriver).length;

  double get totalPrice => pricePerSeat * selectedSeats.length;

  String get formattedPrice => '${_formatAmount(totalPrice.round())} FCFA';

  String get selectionLabel {
    final selected = selectedSeats;
    if (selected.isEmpty) return '—';
    final labels = selected.map((s) => s.config.label).join(', ');
    return selected.length == 1 ? 'Place #$labels' : 'Places #$labels';
  }

  /// Sélectionne/désélectionne un siège. Renvoie un message à afficher si
  /// la sélection est refusée (limite de places atteinte), sinon `null`.
  String? toggleSeat(String seatId) {
    final idx = _seats.indexWhere((s) => s.config.id == seatId);
    if (idx == -1) return null;

    final tapped = _seats[idx];
    if (!tapped.isInteractive) return null;

    if (tapped.isSelected) {
      _seats[idx] = tapped.copyWith(status: SeatStatus.available);
    } else if (selectedSeats.length >= maxSelectable) {
      if (maxSelectable <= 0) return 'Ce trajet est complet.';
      return maxSelectable == 1
          ? 'Il ne reste qu\'une place sur ce trajet.'
          : 'Il ne reste que $maxSelectable places sur ce trajet.';
    } else {
      _seats[idx] = tapped.copyWith(status: SeatStatus.selected);
    }

    notifyListeners();
    return null;
  }

  static String _formatAmount(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
