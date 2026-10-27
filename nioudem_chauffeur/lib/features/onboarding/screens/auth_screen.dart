import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/step_auth_flow.dart';
import '../../../providers/app_provider.dart';

/// Connexion / inscription chauffeur, page par page. Un nouveau compte
/// devient automatiquement chauffeur (`AppProvider.register`).
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return StepAuthFlow(
      welcomeTitle: 'FOJËM Pro',
      welcomeSubtitle: 'Publiez vos trajets et gérez vos passagers.',
      onLogin: (login, password) async {
        final ok = await app.login(login: login, password: password);
        return ok ? null : AuthFailure(app.lastError ?? 'Connexion impossible.');
      },
      onSignup: (data) async {
        final ok = await app.register(
          fullName: data.fullName,
          email: data.email,
          password: data.password,
          phoneNumber: data.phoneNumber,
          gender: data.gender,
        );
        return ok ? null : AuthFailure(app.lastError ?? 'Inscription impossible.');
      },
      onDone: () => context.go('/home'),
    );
  }
}
