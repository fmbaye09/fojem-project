/// Erreur API honnête : porte un message utilisateur clair plutôt que de
/// laisser fuiter une `DioException` brute jusqu'à l'UI. [statusCode] est
/// null pour une erreur réseau/timeout (pas de réponse serveur du tout).
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// Erreurs de validation Laravel (422), champ -> liste de messages.
  final Map<String, List<String>>? fieldErrors;

  const ApiException(this.message, {this.statusCode, this.fieldErrors});

  bool get isUnauthorized => statusCode == 401;
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => message;
}
