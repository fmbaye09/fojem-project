/// Configuration centralisée du backend Laravel FOJËM.
///
/// [baseUrl] pointe par défaut vers l'instance de production. Pour du
/// développement local contre `php artisan serve`, changez cette constante
/// (ex. `http://10.0.2.2:8000/api` depuis un émulateur Android, ou
/// `http://127.0.0.1:8000/api` depuis le web/desktop).
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'http://169.58.156.95:8081/api';

  /// Délai avant abandon d'une requête — l'app doit rester utilisable même
  /// avec un réseau mobile médiocre, sans attendre indéfiniment non plus.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
