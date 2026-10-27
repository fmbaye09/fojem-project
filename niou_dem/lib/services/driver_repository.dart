import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/driver.dart';

/// Cache mémoire complémentaire des profils chauffeur déjà vus (`Trip.driver`
/// embarqué par `driver_profile.user` dans les réponses `/trips/*`, ou déjà
/// résolus via [DriverRepository.fetch]) — évite un aller-retour réseau
/// superflu. La source de vérité reste désormais l'API
/// (`GET /api/drivers/{id}`), pas ce cache : voir [DriverRepository.fetch].
class DriverCache {
  DriverCache._();
  static final DriverCache instance = DriverCache._();

  final Map<String, Driver> _byId = {};

  void put(Driver? driver) {
    if (driver != null && driver.id.isNotEmpty) _byId[driver.id] = driver;
  }

  Driver? get(String id) => _byId[id];
}

/// Profils chauffeur publics via l'API Laravel (`GET /api/drivers/{id}`).
///
/// ATTENTION : `{id}` doit être l'id de la ligne `drivers` (comme partout
/// ailleurs dans l'API, ex. `/admin/drivers/{id}/documents`), **pas** l'id
/// `users` — voir `fojem_backend/README.md`, section "Profils publics".
class DriverRepository {
  final ApiClient _client;

  DriverRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  /// Résout un profil chauffeur par id. Sert d'abord le cache mémoire (utile
  /// pour un chauffeur déjà croisé pendant la navigation), sinon interroge
  /// `GET /drivers/{id}` et alimente le cache avec le résultat.
  Future<Driver?> fetch(String driverId) async {
    if (driverId.isEmpty) return null;
    final cached = DriverCache.instance.get(driverId);
    if (cached != null) return cached;

    try {
      final response = await _client.get('/drivers/$driverId');
      final driverJson = response['driver'] as Map<String, dynamic>?;
      if (driverJson == null) return null;
      final driver = Driver.fromPublicProfileApi(driverJson);
      DriverCache.instance.put(driver);
      return driver;
    } on ApiException {
      return null;
    }
  }
}
