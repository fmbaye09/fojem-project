import 'package:dio/dio.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'token_storage.dart';

/// Routes publiques (pas de header Authorization, pas de logout auto sur 401)
/// — uniquement l'inscription/connexion et la recherche publique de trajets.
bool _isPublicPath(String path) {
  return path.contains('/auth/register') ||
      path.contains('/auth/login') ||
      path.contains('/trips/search');
}

/// Client HTTP central pour l'API Laravel FOJEM. Injecte automatiquement le
/// token Sanctum stocké de façon sécurisée, et centralise la gestion des
/// erreurs réseau/timeout/401 pour que chaque repository n'ait pas à
/// réinventer sa propre gestion d'erreurs.
class ApiClient {
  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Appelé quand une requête authentifiée reçoit un 401 (token expiré/
  /// révoqué) — brancher sur AppProvider.signOut() + redirection connexion.
  /// Statique : chaque repository crée sa propre instance, le callback doit
  /// donc être partagé par toutes pour qu'un 401 n'importe où déconnecte.
  static void Function()? onUnauthorized;

  ApiClient({Dio? dio, TokenStorage? tokenStorage})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: ApiConfig.connectTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              headers: const {'Accept': 'application/json'},
            )),
        _tokenStorage = tokenStorage ?? TokenStorage() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (!_isPublicPath(options.path)) {
          final token = await _tokenStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401 && !_isPublicPath(error.requestOptions.path)) {
          onUnauthorized?.call();
        }
        handler.next(error);
      },
    ));
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _request(() => _dio.get(path, queryParameters: query));

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data}) =>
      _request(() => _dio.post(path, data: data));

  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? data}) =>
      _request(() => _dio.patch(path, data: data));

  /// Envoi `multipart/form-data` (upload de fichiers : photo de profil,
  /// documents chauffeur). Dio pose lui-même le `Content-Type` avec la
  /// bonne frontière quand `data` est un [FormData]. Délai d'envoi allongé :
  /// une photo de quelques Mo sur réseau mobile dépasse vite les délais
  /// pensés pour du JSON.
  Future<Map<String, dynamic>> postMultipart(String path, FormData data) =>
      _request(() => _dio.post(
            path,
            data: data,
            options: Options(sendTimeout: ApiConfig.uploadTimeout),
          ));

  Future<Map<String, dynamic>> _request(Future<Response> Function() call) async {
    try {
      final response = await call();
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      // Laravel paginate() renvoie un objet ; certaines routes pourraient en
      // théorie renvoyer une liste brute — on l'enveloppe pour garder une
      // interface uniforme côté repositories.
      return {'data': data};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final response = e.response;
    if (response == null) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const ApiException(
              'Le serveur met trop de temps à répondre. Vérifiez votre connexion et réessayez.');
        case DioExceptionType.connectionError:
          return const ApiException(
              'Impossible de joindre le serveur. Vérifiez votre connexion internet.');
        default:
          return ApiException(e.message ?? 'Une erreur réseau est survenue.');
      }
    }

    final body = response.data;
    String message = 'Une erreur est survenue (${response.statusCode}).';
    Map<String, List<String>>? fieldErrors;

    if (body is Map<String, dynamic>) {
      if (body['message'] is String) message = body['message'] as String;
      final errors = body['errors'];
      if (errors is Map) {
        fieldErrors = errors.map((key, value) => MapEntry(
              key.toString(),
              (value as List).map((v) => v.toString()).toList(),
            ));
        // Laravel met le premier message de validation à la racine côté
        // affichage utilisateur si aucun message générique n'a été fourni.
        if (body['message'] == null && fieldErrors.isNotEmpty) {
          message = fieldErrors.values.first.first;
        }
      }
    }

    return ApiException(message, statusCode: response.statusCode, fieldErrors: fieldErrors);
  }
}
