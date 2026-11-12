import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'onboarding (3 slides) n'est montré qu'à la première ouverture.
class OnboardingFlag {
  OnboardingFlag._();

  static const _key = 'fojem_onboarded';

  static Future<bool> isDone() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (e) {
      debugPrint('[OnboardingFlag] lecture impossible : $e');
      return false;
    }
  }

  static Future<void> markDone() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (e) {
      debugPrint('[OnboardingFlag] écriture impossible : $e');
    }
  }
}
