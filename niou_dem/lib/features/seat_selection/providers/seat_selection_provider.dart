import 'package:flutter/material.dart';
import '../../../models/trip.dart';
import '../../../models/vehicle.dart';
import '../models/seat.dart';

/// Sièges réels du trajet demandé : plan dérivé du véhicule du chauffeur
/// (Phase 8), prix réel du trajet (Phase 7) et sièges déjà occupés reflétant
/// `seatsAvailable`/`occupiedSeatIds` — plus de plan Sprinter/prix fixes.
class SeatSelectionProvider extends ChangeNotifier {
  final VehicleType vehicleType;
  final double pricePerSeat;
  final List<SeatState> _seats;

  factory SeatSelectionProvider.forTrip(Trip trip) {
    return SeatSelectionProvider._(
      vehicleType: trip.vehicleType,
      pricePerSeat: trip.pricePerSeat,
      occupiedSeatIds: trip.occupiedSeatIds.toSet(),
    );
  }

  SeatSelectionProvider._({
    required this.vehicleType,
    required this.pricePerSeat,
    required Set<String> occupiedSeatIds,
  }) : _seats = seatLayoutFor(vehicleType).map((c) {
          if (c.initialStatus == SeatStatus.driver) {
            return SeatState(config: c, status: SeatStatus.driver);
          }
          final status = occupiedSeatIds.contains(c.id) ? SeatStatus.occupied : SeatStatus.available;
          return SeatState(config: c, status: status);
        }).toList();

  List<SeatState> get seats => List.unmodifiable(_seats);

  SeatState? get selectedSeat =>
      _seats.cast<SeatState?>().firstWhere(
        (s) => s!.isSelected,
        orElse: () => null,
      );

  int get availableCount => _seats.where((s) => s.isAvailable).length;

  int get totalPassengerSeats => _seats.where((s) => !s.isDriver).length;

  double get totalPrice => selectedSeat != null ? pricePerSeat : 0;

  String get formattedPrice => '${_formatAmount(totalPrice.round())} FCFA';

  String get selectionLabel =>
      selectedSeat != null ? 'Place #${selectedSeat!.config.label}' : '—';

  void toggleSeat(String seatId) {
    final idx = _seats.indexWhere((s) => s.config.id == seatId);
    if (idx == -1) return;

    final tapped = _seats[idx];
    if (!tapped.isInteractive) return;

    for (int i = 0; i < _seats.length; i++) {
      if (_seats[i].isSelected) {
        _seats[i] = _seats[i].copyWith(status: SeatStatus.available);
      }
    }

    if (!tapped.isSelected) {
      _seats[idx] = tapped.copyWith(status: SeatStatus.selected);
    }

    notifyListeners();
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
