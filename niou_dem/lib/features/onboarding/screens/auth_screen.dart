import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/phone_auth_flow.dart';
import '../../../providers/app_provider.dart';

/// Connexion / inscription client : numéro, code reçu, puis nom si nouveau.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  static AuthFailure _failure(Object e) =>
      AuthFailure(e is ApiException ? e.message : 'Une erreur est survenue. Réessayez.');

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return PhoneAuthFlow(
      onSendCode: (phone, channel) async {
        try {
          final sent = await app.sendCode(phone, channel: channel.name);
          return SendCodeResult.sent(resendIn: sent.resendIn, devCode: sent.devCode);
        } catch (e) {
          return SendCodeResult.failed(_failure(e));
        }
      },
      onCheckCode: (phone, code) async {
        try {
          final check = await app.verifyCode(phone, code);
          final token = check.signupToken;
          return token != null ? CheckCodeResult.newCustomer(token) : const CheckCodeResult.signedIn();
        } catch (e) {
          return CheckCodeResult.failed(_failure(e));
        }
      },
      onCreateAccount: (token, firstName, lastName) async {
        try {
          await app.registerWithCode(signupToken: token, firstName: firstName, lastName: lastName);
          return null;
        } catch (e) {
          return _failure(e);
        }
      },
      onDone: () => context.go('/home'),
      onOpenTerms: () => context.push('/profile/terms'),
      onOpenPrivacy: () => context.push('/profile/privacy'),
    );
  }
}
