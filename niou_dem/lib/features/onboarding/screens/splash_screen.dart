import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../providers/app_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fojem_button.dart';
import '../../../core/widgets/fojem_logo.dart';

/// Écran d'accueil / intro (design/screens/fojem_onboarding_auth.png,
/// premier écran) — remplace l'ancien trio Splash animé + Onboarding 3 slides
/// + choix de rôle en carte : plus de slides marketing, juste l'accroche et
/// un bouton d'entrée direct vers le flow d'inscription.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _checkAuth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppProvider>();
      if (!app.isLoading && app.isLoggedIn) {
        context.go('/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    final app = context.watch<AppProvider>();
    if (!app.isLoading && app.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home');
      });
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoWidth = screenWidth * 0.55 < 160
        ? 160.0
        : (screenWidth * 0.55 > 260 ? 260.0 : screenWidth * 0.55);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 0.9,
            colors: [AppColors.accentLight, AppColors.background],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Center(child: FojemLogo(width: logoWidth)),
                const SizedBox(height: 18),
                Text(
                  'CO-VOITURAGE INTERURBAIN',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 1.6,
                  ),
                ),
                if (app.isLoading) ...[
                  const Spacer(flex: 4),
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 40),
                ] else ...[
                  const Spacer(flex: 4),
                  FojemButton.primary(
                    label: 'Entrer dans l\'application',
                    suffixIcon: Icons.arrow_forward,
                    onPressed: () {
                      if (app.isLoggedIn) {
                        context.go('/home');
                      } else {
                        context.go('/role-selection');
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
