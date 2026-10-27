/// Erreur normalisée levée par [ApiClient] — traduit les échecs Dio (réseau,
/// timeout, HTTP 4xx/5xx) en un message clair pour l'UI, sans jamais laisser
/// une exception réseau brute remonter silencieusement jusqu'à l'écran.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// Erreurs de validation Laravel (422) : `{champ: [messages]}`.
  final Map<String, List<String>>? fieldErrors;

  const ApiException(this.message, {this.statusCode, this.fieldErrors});

  /// Premier message de validation, si disponible — plus précis que
  /// [message] générique pour un champ de formulaire donné.
  String? firstFieldError(String field) {
    final errors = fieldErrors?[field];
    return errors != null && errors.isNotEmpty ? errors.first : null;
  }

  @override
  String toString() => message;
}
