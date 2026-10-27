import 'package:shared_preferences/shared_preferences.dart';

/// Préférence de langue choisie par l'utilisateur, persistée localement.
///
/// L'app ne parle aujourd'hui que français (`MaterialApp.router` a une
/// locale fixe dans `app.dart`) : ce réglage prépare le terrain pour une
/// future localisation complète, il ne change pas encore les textes de
/// l'interface. On le garde honnête côté UI (voir `language_screen.dart`).
class LanguagePreference {
  LanguagePreference._();

  static const String _key = 'app_language_code';

  static const String defaultCode = 'fr';

  static const Map<String, String> labels = {
    'fr': 'Français',
    'wo': 'Wolof',
    'en': 'English',
  };

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultCode;
  }

  static Future<void> save(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }

  static String labelFor(String code) => labels[code] ?? labels[defaultCode]!;
}
