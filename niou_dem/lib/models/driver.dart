import '../core/network/api_config.dart';
import 'vehicle.dart';

class Review {
  final String id;
  final String authorName;
  final double rating;
  final String comment;
  final DateTime date;

  const Review({
    required this.id,
    required this.authorName,
    required this.rating,
    required this.comment,
    required this.date,
  });
}

class Driver {
  final String id;
  final String name;
  final String? photoUrl;
  final double rating;
  final int ratingCount;
  final int totalTrips;
  final Vehicle vehicle;
  final bool isOnline;
  final List<Review> reviews;
  final String phoneNumber;

  const Driver({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.rating,
    this.ratingCount = 0,
    required this.totalTrips,
    required this.vehicle,
    required this.isOnline,
    required this.reviews,
    required this.phoneNumber,
  });

  /// "Mamadou T." : prénom + initiale du nom, comme sur les cartes trajet.
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return parts.first;
    return '${parts.first} ${parts.last[0].toUpperCase()}.';
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  /// Compose un [Driver] à partir de la relation `driver_profile.user`
  /// embarquée sur un trajet/réservation, et du véhicule associé.
  factory Driver.fromApi(Map<String, dynamic> driverProfileJson, {Vehicle? vehicle}) {
    final userJson = driverProfileJson['user'] as Map<String, dynamic>?;
    final rawPhoto = userJson?['profile_photo_url'] as String?;
    return Driver(
      id: userJson?['id'] as String? ?? driverProfileJson['user_id'] as String? ?? '',
      name: userJson?['full_name'] as String? ?? '',
      photoUrl: ApiConfig.resolveMediaUrl(rawPhoto),
      rating: double.tryParse('${driverProfileJson['average_rating'] ?? ''}') ?? 0.0,
      ratingCount: 0,
      totalTrips: int.tryParse('${driverProfileJson['total_trips_completed'] ?? ''}') ?? 0,
      vehicle: vehicle ??
          const Vehicle(
            id: '',
            driverId: '',
            type: VehicleType.septPlaces,
            brand: '',
            model: '',
            color: '',
            plateNumber: '',
          ),
      isOnline: true,
      reviews: const [],
      phoneNumber: userJson?['phone_number'] as String? ?? '',
    );
  }

  /// Construit un [Driver] à partir de `GET /api/drivers/{id}` (profil
  /// chauffeur public : `id, full_name, profile_photo_url, average_rating,
  /// total_trips_completed, recent_reviews`).
  factory Driver.fromPublicProfileApi(Map<String, dynamic> map) {
    final reviewsJson = (map['recent_reviews'] as List?) ?? const [];
    final reviews = reviewsJson.map((raw) {
      final reviewMap = raw as Map<String, dynamic>;
      final subRatings = <num>[
        for (final key in [
          'punctuality_rating',
          'driving_rating',
          'communication_rating',
          'safety_rating',
        ])
          if (reviewMap[key] is num) reviewMap[key] as num,
      ];
      final avgRating = subRatings.isEmpty
          ? 0.0
          : subRatings.reduce((a, b) => a + b) / subRatings.length;
      return Review(
        id: reviewMap['id'] as String? ?? '',
        authorName: 'Voyageur FOJËM',
        rating: avgRating.toDouble(),
        comment: reviewMap['comment'] as String? ?? '',
        date: DateTime.tryParse(reviewMap['created_at'] as String? ?? '') ?? DateTime.now(),
      );
    }).toList();

    final rawPhoto = map['profile_photo_url'] as String?;
    return Driver(
      id: map['id'] as String? ?? '',
      name: map['full_name'] as String? ?? '',
      photoUrl: ApiConfig.resolveMediaUrl(rawPhoto),
      rating: double.tryParse('${map['average_rating'] ?? ''}') ?? 0.0,
      ratingCount: reviews.length,
      totalTrips: int.tryParse('${map['total_trips_completed'] ?? ''}') ?? 0,
      vehicle: const Vehicle(
        id: '',
        driverId: '',
        type: VehicleType.septPlaces,
        brand: '',
        model: '',
        color: '',
        plateNumber: '',
      ),
      isOnline: true,
      reviews: reviews,
      phoneNumber: '',
    );
  }
}
