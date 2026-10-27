import 'package:dio/dio.dart';
import '../storage/secure_token_storage.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// Client HTTP unique vers le backend Laravel FOJËM.
///
/// - Ajoute automatiquement `Authorization: Bearer <token>` (sauf sur
///   `/auth/register` et `/auth/login`, qui n'ont pas encore de token).
/// - Traduit toute erreur Dio (réseau, timeout, 4xx/5xx) en [ApiException]
///   avec un message lisible, jamais une exception brute qui plante l'écran.
/// - Sur un 401 (token expiré/révoqué), déclenche [onUnauthorized] — branché
///   par [AppProvider] pour déconnecter proprement et rediriger vers l'écran
///   de connexion, plutôt que de laisser l'app dans un état incohérent.
class ApiClient {
  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  final SecureTokenStorage _tokenStorage;

  /// Appelé une fois qu'une requête authentifiée reçoit un 401. `null` par
  /// défaut tant qu'[AppProvider] ne s'est pas enregistré.
  void Function()? onUnauthorized;

  ApiClient._internal({SecureTokenStorage? tokenStorage})
      : _tokenStorage = tokenStorage ?? SecureTokenStorage() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {'Accept': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final isAuthEndpoint = options.path.contains('/auth/register') ||
            options.path.contains('/auth/login');
        if (!isAuthEndpoint) {
          final token = await _tokenStorage.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          onUnauthorized?.call();
        }
        handler.next(error);
      },
    ));
  }

  /// Permet d'injecter un [Dio] de test (mock/mémoire) sans passer par le
  /// singleton — utilisé par les tests des repositories.
  factory ApiClient.test(Dio dio) {
    final client = ApiClient._internal();
    client._dio = dio;
    return client;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    return _unwrap(() => _dio.get(path, queryParameters: _clean(query)));
  }

  Future<Map<String, dynamic>> post(String path, {dynamic data}) async {
    return _unwrap(() => _dio.post(path, data: data));
  }

  Future<Map<String, dynamic>> patch(String path, {dynamic data}) async {
    return _unwrap(() => _dio.patch(path, data: data));
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final result = <String, dynamic>{};
    for (final entry in query.entries) {
      if (entry.value != null) result[entry.key] = entry.value;
    }
    return result;
  }

  Future<Map<String, dynamic>> _unwrap(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data == null) return const {};
      // Ex. une liste JSON brute — on l'enveloppe pour garder une signature
      // homogène côté appelant.
      return {'data': data};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          'La connexion au serveur a expiré. Vérifiez votre réseau et réessayez.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          'Impossible de joindre le serveur FOJËM. Vérifiez votre connexion internet.',
        );
      case DioExceptionType.badCertificate:
        return const ApiException('Connexion sécurisée refusée par le serveur.');
      case DioExceptionType.cancel:
        return const ApiException('Requête annulée.');
      case DioExceptionType.badResponse:
        return _fromResponse(e);
      case DioExceptionType.unknown:
      default:
        // `default` couvre aussi les valeurs ajoutées par de futures
        // versions de dio (ex. transformTimeout) sans casser le build.
        return ApiException(
          'Une erreur réseau est survenue. ${e.message ?? ""}'.trim(),
        );
    }
  }

  ApiException _fromResponse(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    String message = 'Une erreur est survenue (code $status).';
    Map<String, List<String>>? fieldErrors;

    if (body is Map<String, dynamic>) {
      if (body['message'] is String) message = body['message'] as String;
      final errors = body['errors'];
      if (errors is Map<String, dynamic>) {
        fieldErrors = errors.map(
          (key, value) => MapEntry(key, (value as List).map((v) => v.toString()).toList()),
        );
        final firstList = fieldErrors.values.isNotEmpty ? fieldErrors.values.first : null;
        final firstError = firstList != null && firstList.isNotEmpty ? firstList.first : null;
        if (firstError != null) message = firstError;
      }
    }

    if (status == 401) message = 'Session expirée. Reconnectez-vous.';
    if (status == 403 && body is! Map) message = 'Action non autorisée.';
    if (status == 429) message = 'Trop de tentatives. Réessayez dans quelques instants.';
    if (status != null && status >= 500) {
      message = 'Le serveur FOJËM rencontre un problème. Réessayez plus tard.';
    }

    return ApiException(message, statusCode: status, fieldErrors: fieldErrors);
  }
}
