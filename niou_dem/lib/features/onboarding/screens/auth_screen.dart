import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/step_auth_flow.dart';
import '../../../providers/app_provider.dart';

/// Connexion / inscription voyageur, page par page.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  static AuthFailure _failure(Object e, String fallback) {
    if (e is ApiException) {
      final field = e.fieldErrors?.keys.isNotEmpty == true ? e.fieldErrors!.keys.first : null;
      return AuthFailure(e.message, field: field);
    }
    return AuthFailure(fallback);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return StepAuthFlow(
      welcomeTitle: 'Bienvenue chez FOJËM',
      welcomeSubtitle: 'Trouvez un trajet entre villes, avec des chauffeurs vérifiés.',
      onLogin: (login, password) async {
        try {
          await app.login(
            email: login.contains('@') ? login : null,
            phoneNumber: login.contains('@') ? null : login,
            password: password,
          );
          return null;
        } catch (e) {
          return _failure(e, 'Connexion impossible. Réessayez.');
        }
      },
      onSignup: (data) async {
        try {
          await app.register(
            fullName: data.fullName,
            email: data.email,
            password: data.password,
            phoneNumber: data.phoneNumber,
            gender: data.gender,
          );
          return null;
        } catch (e) {
          return _failure(e, 'Inscription impossible. Réessayez.');
        }
      },
      onDone: () => context.go('/home'),
    );
  }
}
