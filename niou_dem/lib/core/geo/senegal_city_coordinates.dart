import 'geo_location.dart';

/// Coordonnées approximatives (centroïde ville) pour les villes listées dans
/// `senegalCities`. Sert de repère par défaut quand l'utilisateur choisit une
/// ville par nom plutôt qu'un point précis sur la carte (Phase 5) — la
/// précision est celle d'un centre-ville, pas d'une adresse exacte.
const Map<String, GeoLocation> senegalCityCoordinates = {
  'Dakar': GeoLocation(lat: 14.6928, lng: -17.4467, address: 'Dakar'),
  'Thiès': GeoLocation(lat: 14.7910, lng: -16.9359, address: 'Thiès'),
  'Mbour': GeoLocation(lat: 14.4198, lng: -16.9641, address: 'Mbour'),
  'Saint-Louis': GeoLocation(lat: 16.0179, lng: -16.4896, address: 'Saint-Louis'),
  'Ziguinchor': GeoLocation(lat: 12.5665, lng: -16.2733, address: 'Ziguinchor'),
  'Kaolack': GeoLocation(lat: 14.1652, lng: -16.0726, address: 'Kaolack'),
  'Tambacounda': GeoLocation(lat: 13.7707, lng: -13.6673, address: 'Tambacounda'),
  'Touba': GeoLocation(lat: 14.8500, lng: -15.8833, address: 'Touba'),
  'Diourbel': GeoLocation(lat: 14.6559, lng: -16.2333, address: 'Diourbel'),
  'Louga': GeoLocation(lat: 15.6173, lng: -16.2240, address: 'Louga'),
  'Fatick': GeoLocation(lat: 14.3390, lng: -16.4110, address: 'Fatick'),
  'Kolda': GeoLocation(lat: 12.8983, lng: -14.9412, address: 'Kolda'),
  'Sédhiou': GeoLocation(lat: 12.7081, lng: -15.5569, address: 'Sédhiou'),
  'Kaffrine': GeoLocation(lat: 14.1059, lng: -15.5508, address: 'Kaffrine'),
  'Kédougou': GeoLocation(lat: 12.5556, lng: -12.1746, address: 'Kédougou'),
  'Matam': GeoLocation(lat: 15.6559, lng: -13.2548, address: 'Matam'),
};

/// Retourne la coordonnée connue pour `cityName`, ou Dakar par défaut si la
/// ville n'est pas dans la liste (ne devrait pas arriver — le sélecteur de
/// ville n'offre que des villes de `senegalCities`).
GeoLocation coordinatesForCity(String cityName) =>
    senegalCityCoordinates[cityName] ?? senegalCityCoordinates['Dakar']!;
