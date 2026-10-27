import 'package:shared_preferences/shared_preferences.dart';

/// Persistance locale simple de la langue choisie par l'utilisateur.
///
/// Note : l'app ne propose pour l'instant qu'une interface en français
/// (voir `FojemApp.supportedLocales`) — cette préférence est donc
/// stockée pour être reprise plus tard par une vraie localisation FR/Wolof/EN,
/// mais n'a pas encore d'effet visuel sur l'app elle-même.
class LanguagePreference {
  LanguagePreference._();

  static const _key = 'app_language_code';
  static const defaultCode = 'fr';

  static Future<String> getLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultCode;
  }

  static Future<void> setLanguageCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }
}
