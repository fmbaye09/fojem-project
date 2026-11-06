import 'package:geolocator/geolocator.dart';

import '../core/geo/geo_location.dart';
import 'map/osm_map_service.dart';

/// Libellé d'une position dont l'adresse n'est pas (encore) connue.
const kCurrentPositionLabel = 'Ma position';

/// Position actuelle du téléphone, sans adresse : départ par défaut de la
/// recherche. Demande la permission si elle n'a jamais été donnée ; `null`
/// si la localisation est coupée, refusée ou ne répond pas.
Future<GeoLocation?> locateDevice() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      return null;
    }

    // Une position de moins d'un quart d'heure suffit à trouver les départs
    // proches et évite d'attendre le GPS.
    final last = await Geolocator.getLastKnownPosition();
    Position? position =
        last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 15) ? last : null;
    if (position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        position = last;
      }
    }
    if (position == null) return null;
    return GeoLocation(lat: position.latitude, lng: position.longitude, address: kCurrentPositionLabel);
  } catch (_) {
    return null;
  }
}

/// Adresse et quartier d'une position ([locateDevice]) ; `null` sans réseau
/// ou si le géocodage échoue, la position garde alors son libellé.
Future<GeoLocation?> describeLocation(GeoLocation position) async {
  try {
    final place = await OsmMapService()
        .reverseGeocode(position.lat, position.lng)
        .timeout(const Duration(seconds: 8));
    // En cas d'erreur, le géocodage renvoie les coordonnées comme adresse.
    if (place.locality == null && place.address == '${position.lat}, ${position.lng}') return null;
    return place;
  } catch (_) {
    return null;
  }
}
