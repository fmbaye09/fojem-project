import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/onboarding_flag.dart';
import '../../../core/widgets/glow.dart';

/// Trois slides de présentation, montrées à la première ouverture.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _slides = [
    (
      title: 'Trouvez des voyageurs sur votre route',
      body: 'Voyagez avec des chauffeurs vérifiés, pour des trajets sûrs et abordables entre les villes du Sénégal.',
    ),
    (
      title: 'Montez au plus près de chez vous',
      body: 'Les chauffeurs fixent des points de rendez-vous sur leur route : choisissez où monter et où descendre.',
    ),
    (
      title: 'Voyagez en toute sérénité',
      body: 'Billet QR code, suivi du chauffeur en direct et messagerie intégrée.',
    ),
  ];

  int _index = 0;

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await OnboardingFlag.markDone();
    if (mounted) context.go('/role-selection');
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_index];
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.sunriseGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text('Passer',
                        style: AppTextStyles.bodySemibold.copyWith(color: AppColors.textSecondary)),
                  ),
                ),
                Expanded(
                  child: RiseIn(
                    key: ValueKey(_index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OnboardingArt(index: _index),
                        const SizedBox(height: 48),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.display.copyWith(fontSize: 30, height: 1.15),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var k = 0; k < _slides.length; k++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: k == _index ? 32 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: k == _index ? AppColors.primary : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                GlowButton(
                  label: _isLast ? 'Commencer' : 'Suivant',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _isLast ? _finish : () => setState(() => _index++),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Illustrations des slides, composées avec le kit néomorphique.
class OnboardingArt extends StatelessWidget {
  final int index;

  const OnboardingArt({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    switch (index) {
      case 0:
        return SizedBox(
          width: 256,
          height: 256,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
                ),
              ),
              FloatingMotion(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const NeuBox(
                      radius: 24,
                      padding: EdgeInsets.all(26),
                      child: Icon(Icons.groups_rounded, size: 44, color: AppColors.primaryGlow),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppColors.glowShadow,
                      ),
                      child: const Icon(Icons.directions_car_rounded, size: 44, color: AppColors.onPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 1:
        return NeuBox(
          radius: 32,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 256,
            height: 256,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _RoutePainter())),
                const Positioned(left: 24, bottom: 32, child: _Pin(color: AppColors.primary)),
                const Positioned(
                  right: 24,
                  top: 24,
                  child: FloatingMotion(child: _Pin(color: AppColors.accent)),
                ),
              ],
            ),
          ),
        );
      default:
        return Container(
          width: 256,
          height: 256,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: AppColors.neuShadow,
          ),
          alignment: Alignment.center,
          child: FloatingMotion(
            child: Container(
              width: 144,
              height: 144,
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: AppColors.glowShadow,
              ),
              child: const Icon(Icons.verified_user_rounded, size: 64, color: AppColors.onPrimary),
            ),
          ),
        );
    }
  }
}

class _Pin extends StatelessWidget {
  final Color color;

  const _Pin({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x3307232F), blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: const Icon(Icons.place_rounded, color: AppColors.onPrimary, size: 22),
    );
  }
}

/// Route stylisée entre deux repères.
class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    Path curve(double dx, double dy) => Path()
      ..moveTo((40 + dx) * s, (160 + dy) * s)
      ..cubicTo((70 + dx) * s, (120 + dy) * s, (110 + dx) * s, (120 + dy) * s, (160 + dx) * s, (40 + dy) * s);
    canvas.drawPath(
      curve(0, 0),
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 6 * s
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      curve(8, 5),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.5)
        ..strokeWidth = 3 * s
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) => false;
}
