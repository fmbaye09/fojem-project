import '../core/geo/geo_location.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/trip.dart';
import 'driver_repository.dart';

/// Trajets via l'API Laravel (`/api/trips/*`).
///
/// Le backend n'a pas d'endpoint "liste tous les trajets ouverts" — seul
/// `GET /trips/search` existe, et il exige un couple origine+destination
/// (recherche géographique par rayon, voir `TripController::search()` /
/// `Trip::scopeNear()`). Les écrans qui avaient besoin d'un univers de
/// trajets "actifs à venir" (accueil, onglet Trajets) ont donc été adaptés
/// pour passer par [search] avec les coordonnées choisies, plutôt que de
/// filtrer côté client une liste globale qui n'existe plus.
class TripSearchResult {
  final List<Trip> trips;
  final List<Trip> suggestions;

  const TripSearchResult({
    required this.trips,
    this.suggestions = const [],
  });
}

class TripRepository {
  final ApiClient _client;

  TripRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  /// Recherche publique : trajets dont un point de rendez-vous est à moins
  /// de [radiusM] mètres de [origin] et un point suivant à moins de [radiusM]
  /// de [destination] (chaque résultat porte son `match`), avec suggestions
  /// de repli si aucun trajet ne correspond.
  Future<TripSearchResult> searchWithSuggestions({
    required GeoLocation origin,
    required GeoLocation destination,
    int radiusM = 15000,
    bool womenOnly = false,
  }) async {
    final response = await _client.get('/trips/search', query: {
      'origin_lat': origin.lat,
      'origin_lng': origin.lng,
      'destination_lat': destination.lat,
      'destination_lng': destination.lng,
      'radius_m': radiusM,
      if (womenOnly) 'women_only': true,
    });
    final tripsRaw = response['trips'] as List? ?? [];
    final suggestionsRaw = response['suggestions'] as List? ?? [];

    final trips = tripsRaw.map((t) {
      final trip = Trip.fromApi(t as Map<String, dynamic>);
      DriverCache.instance.put(trip.driver);
      return trip;
    }).toList();

    final suggestions = suggestionsRaw.map((t) {
      final trip = Trip.fromApi(t as Map<String, dynamic>);
      DriverCache.instance.put(trip.driver);
      return trip;
    }).toList();

    return TripSearchResult(trips: trips, suggestions: suggestions);
  }

  /// Comme [searchWithSuggestions], sans les suggestions.
  Future<List<Trip>> search({
    required GeoLocation origin,
    required GeoLocation destination,
    int radiusM = 15000,
    bool womenOnly = false,
  }) async {
    final result = await searchWithSuggestions(
      origin: origin,
      destination: destination,
      radiusM: radiusM,
      womenOnly: womenOnly,
    );
    return result.trips;
  }

  Future<Trip?> fetch(String tripId) async {
    try {
      final response = await _client.get('/trips/$tripId');
      final tripJson = response['trip'] as Map<String, dynamic>?;
      if (tripJson == null) return null;
      final trip = Trip.fromApi(tripJson);
      DriverCache.instance.put(trip.driver);
      return trip;
    } on ApiException {
      return null;
    }
  }

  /// Trajets du chauffeur connecté (`GET /trips/mine`) — non utilisé côté
  /// app Passager, gardé pour compat/complétude de l'interface.
  Future<List<Trip>> fetchForDriver() async {
    final response = await _client.get('/trips/mine');
    final data = (response['data'] as List?) ?? (response['trips'] as List?) ?? [];
    return data.map((t) => Trip.fromApi(t as Map<String, dynamic>)).toList();
  }
}
