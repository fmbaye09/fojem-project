import 'trip.dart';
import 'trip_stop.dart';

enum BookingStatus { pending, confirmed, refused, cancelled, completed }

BookingStatus _statusFromApi(String? status) {
  switch (status) {
    case 'pending_driver':
      return BookingStatus.pending;
    case 'confirmed':
      return BookingStatus.confirmed;
    case 'rejected':
      return BookingStatus.refused;
    case 'cancelled_passenger':
    case 'cancelled_driver':
    case 'no_show':
      return BookingStatus.cancelled;
    case 'completed':
      return BookingStatus.completed;
    default:
      return BookingStatus.pending;
  }
}

class Booking {
  final String id;
  final String tripId;
  final String passengerId;
  /// Nombre de places réservées, sous forme de texte (`seat_count`).
  final String seatId;

  /// Sièges choisis sur le plan du véhicule ; vide pour les anciennes
  /// réservations faites sans plan.
  final List<String> seatNumbers;
  final double price;
  final BookingStatus status;
  final DateTime bookedAt;
  final String confirmationCode;
  final String passengerName;
  final String passengerPhone;
  final DateTime? startedAt;
  final bool hasHeavyLuggage;
  final List<String> luggagePhotoUrls;

  /// Où le passager monte et descend (points de rendez-vous du chauffeur).
  final TripStop? boardingStop;
  final TripStop? alightingStop;

  final Trip? trip;

  const Booking({
    required this.id,
    required this.tripId,
    required this.passengerId,
    required this.seatId,
    this.seatNumbers = const [],
    required this.price,
    required this.status,
    required this.bookedAt,
    required this.confirmationCode,
    required this.passengerName,
    required this.passengerPhone,
    this.hasHeavyLuggage = false,
    this.luggagePhotoUrls = const [],
    this.startedAt,
    this.boardingStop,
    this.alightingStop,
    this.trip,
  });

  int get seatsBooked => int.tryParse(seatId) ?? 1;

  /// « Place #3 », « Places #1, 3 », ou « 2 places » sans numéros connus.
  String get seatLabel {
    if (seatNumbers.isEmpty) {
      return seatsBooked > 1 ? '$seatsBooked places' : '1 place';
    }
    final numbers = seatNumbers.join(', ');
    return seatNumbers.length > 1 ? 'Places #$numbers' : 'Place #$numbers';
  }
  double get totalPrice => price;
  bool get isBoarded => startedAt != null;

  String get statusLabel {
    switch (status) {
      case BookingStatus.pending:
        return 'En attente';
      case BookingStatus.confirmed:
        return isBoarded ? 'À bord' : 'Confirmé';
      case BookingStatus.refused:
        return 'Refusé';
      case BookingStatus.cancelled:
        return 'Annulé';
      case BookingStatus.completed:
        return 'Terminé';
    }
  }

  factory Booking.fromApi(Map<String, dynamic> map, {Trip? trip}) {
    final tripObj = trip ??
        ((map['trip'] is Map<String, dynamic>)
            ? Trip.fromApi(map['trip'] as Map<String, dynamic>)
            : null);

    final passenger = map['passenger'] is Map<String, dynamic>
        ? map['passenger'] as Map<String, dynamic>
        : null;

    final name = (passenger?['full_name'] as String?) ??
        (passenger?['name'] as String?) ??
        '';
    final phone = (passenger?['phone_number'] as String?) ??
        (passenger?['phone'] as String?) ??
        '';

    final photosList = <String>[];
    if (map['luggage_photos'] is List) {
      for (final p in (map['luggage_photos'] as List)) {
        if (p is Map<String, dynamic> && p['photo_url'] is String) {
          photosList.add(p['photo_url'] as String);
        } else if (p is String) {
          photosList.add(p);
        }
      }
    }

    final hasHeavy = map['has_heavy_luggage'] == true ||
        map['has_heavy_luggage'] == 1 ||
        photosList.isNotEmpty;

    return Booking(
      id: map['id'] as String? ?? '',
      tripId: map['trip_id'] as String? ?? '',
      passengerId: map['passenger_id'] as String? ?? '',
      seatId: '${map['seat_count'] ?? 1}',
      seatNumbers: [
        for (final seat in (map['seat_numbers'] as List? ?? const [])) '$seat',
      ],
      price: double.tryParse('${map['price_charged']}') ?? 0,
      status: _statusFromApi(map['status'] as String?),
      bookedAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      confirmationCode: map['departure_code'] as String? ?? '',
      passengerName: name,
      passengerPhone: phone,
      hasHeavyLuggage: hasHeavy,
      luggagePhotoUrls: photosList,
      startedAt: DateTime.tryParse(map['started_at'] as String? ?? ''),
      boardingStop: map['boarding_stop'] is Map<String, dynamic>
          ? TripStop.fromJson(map['boarding_stop'] as Map<String, dynamic>)
          : null,
      alightingStop: map['alighting_stop'] is Map<String, dynamic>
          ? TripStop.fromJson(map['alighting_stop'] as Map<String, dynamic>)
          : null,
      trip: tripObj,
    );
  }

  Booking copyWith({
    BookingStatus? status,
    Trip? trip,
    DateTime? startedAt,
    bool? hasHeavyLuggage,
    List<String>? luggagePhotoUrls,
  }) {
    return Booking(
      id: id,
      tripId: tripId,
      passengerId: passengerId,
      seatId: seatId,
      seatNumbers: seatNumbers,
      price: price,
      status: status ?? this.status,
      bookedAt: bookedAt,
      confirmationCode: confirmationCode,
      passengerName: passengerName,
      passengerPhone: passengerPhone,
      hasHeavyLuggage: hasHeavyLuggage ?? this.hasHeavyLuggage,
      luggagePhotoUrls: luggagePhotoUrls ?? this.luggagePhotoUrls,
      startedAt: startedAt ?? this.startedAt,
      boardingStop: boardingStop,
      alightingStop: alightingStop,
      trip: trip ?? this.trip,
    );
  }
}
