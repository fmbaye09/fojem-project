import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'fojem_logo.dart';
import 'glow.dart';

/// Logo FOJËM animé du démarrage : la carte « pop » (rebond + légère
/// rotation), la voiture entre dans le cadre, un anneau de verre pulse
/// derrière (`animate-logo-pop`, `animate-car-drive`, `animate-ring-pulse`).
class AnimatedBrandLogo extends StatefulWidget {
  final double size;

  const AnimatedBrandLogo({super.key, this.size = 128});

  @override
  State<AnimatedBrandLogo> createState() => _AnimatedBrandLogoState();
}

class _AnimatedBrandLogoState extends State<AnimatedBrandLogo> with TickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final AnimationController _drive =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  // 0 → 1,12 → 0,96 → 1 ; rotation -12° → 3° → 0.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.12), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 0.96), weight: 20),
    TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0), weight: 25),
  ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));
  late final Animation<double> _turn = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: -12 / 360, end: 3 / 360), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 3 / 360, end: 0.0), weight: 45),
  ]).animate(_pop);
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _pop, curve: const Interval(0, 0.5, curve: Curves.easeOut));

  // La voiture arrive de la gauche, dépasse un peu, puis se cale.
  late final Animation<double> _carX = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: -1.4, end: 0.06), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 0.06, end: 0.0), weight: 40),
  ]).animate(CurvedAnimation(parent: _drive, curve: const Cubic(0.22, 1, 0.36, 1)));

  Timer? _driveStart;

  @override
  void initState() {
    super.initState();
    _driveStart = Timer(const Duration(milliseconds: 300), _drive.forward);
  }

  @override
  void dispose() {
    _driveStart?.cancel();
    _pop.dispose();
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final radius = size / 4;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: PulseRing(size: size, radius: radius)),
          AnimatedBuilder(
            animation: _pop,
            builder: (_, child) => Opacity(
              opacity: _opacity.value,
              child: Transform.rotate(
                angle: _turn.value * 2 * 3.141592653589793,
                child: Transform.scale(scale: _scale.value, child: child),
              ),
            ),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: const [BoxShadow(color: Color(0x4007232F), blurRadius: 40, offset: Offset(0, 20))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _drive,
                    builder: (_, child) => FractionalTranslation(
                      translation: Offset(_carX.value, 0),
                      child: child,
                    ),
                    child: FojemLogo.icon(size: size * 0.62),
                  ),
                  Positioned(
                    bottom: size * 0.17,
                    child: Container(
                      width: size * 0.44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre de chargement en verre qui se remplit (`animate-load-bar`).
class GlassLoadBar extends StatefulWidget {
  final double width;
  final Duration duration;

  const GlassLoadBar({super.key, this.width = 208, this.duration = const Duration(milliseconds: 2400)});

  @override
  State<GlassLoadBar> createState() => _GlassLoadBarState();
}

class _GlassLoadBarState extends State<GlassLoadBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(const Duration(milliseconds: 400), _c.forward);
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.3), width: 0.5),
      ),
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => FractionallySizedBox(
          widthFactor: Curves.easeInOut.transform(_c.value),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.onPrimary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}
