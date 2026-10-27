import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/onboarding_flag.dart';
import '../../../core/widgets/animated_brand_logo.dart';
import '../../../core/widgets/glow.dart';
import '../../../providers/app_provider.dart';

/// Écran de démarrage animé (template fojem-glow-flow) : logo qui « pop »,
/// nom et slogan qui montent, barre de chargement. À la fin de l'animation
/// (et une fois la session restaurée) : accueil si connecté, onboarding à la
/// première ouverture, sinon écran de bienvenue.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _minDuration = Duration(milliseconds: 2900);
  bool _animationDone = false;
  bool _navigated = false;
  Timer? _animationTimer;

  @override
  void initState() {
    super.initState();
    _animationTimer = Timer(_minDuration, () {
      if (!mounted) return;
      setState(() => _animationDone = true);
      _maybeContinue();
    });
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeContinue() async {
    final app = context.read<AppProvider>();
    if (_navigated || !_animationDone || app.isLoading || app.sessionUnavailable) return;
    _navigated = true;
    if (app.isLoggedIn) {
      context.go('/home');
      return;
    }
    final onboarded = await OnboardingFlag.isDone();
    if (!mounted) return;
    context.go(onboarded ? '/role-selection' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    // La session peut finir de se restaurer après l'animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeContinue();
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.splashGradient),
          child: SafeArea(
            child: SizedBox.expand(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AnimatedBrandLogo(size: 128),
                      const SizedBox(height: 40),
                      RiseIn(
                        delay: const Duration(milliseconds: 700),
                        child: Text(
                          'FOJËM',
                          style: AppTextStyles.display.copyWith(
                            color: AppColors.onPrimary,
                            fontSize: 48,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      RiseIn(
                        delay: const Duration(milliseconds: 900),
                        child: Text(
                          'Partagez la route. Économisez. Voyagez serein.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.onPrimary.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      if (app.sessionUnavailable)
                        _OfflineRetry(message: app.sessionError, onRetry: app.retrySession)
                      else
                        const GlassLoadBar(),
                    ],
                  ),
                  Positioned(
                    bottom: 32,
                    child: Text(
                      'CO-VOITURAGE INTERURBAIN',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.onPrimary.withValues(alpha: 0.7),
                        fontSize: 11,
                        letterSpacing: 3.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Serveur injoignable au démarrage : la session est conservée, il suffit
/// de réessayer.
class _OfflineRetry extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _OfflineRetry({this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GlassPanel(
        onBrand: true,
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.onPrimary, size: 28),
            const SizedBox(height: 8),
            Text(
              message ?? 'Impossible de joindre le serveur. Vérifiez votre connexion.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.onPrimary),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.onPrimary),
              label: Text('Réessayer',
                  style: AppTextStyles.bodySemibold.copyWith(color: AppColors.onPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
