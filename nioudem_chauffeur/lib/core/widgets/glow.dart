import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Kit « Glow Flow » : néomorphisme (surfaces en relief / en creux) +
/// glassmorphisme (panneaux translucides floutés), dégradé de marque et
/// animations d'entrée. Reproduit les utilitaires du template
/// fojem-glow-flow (`neu`, `neu-sm`, `neu-inset`, `glass`, `btn-brand`,
/// `animate-rise`, `animate-float`, `animate-ring-pulse`).

// ─── Surfaces ──────────────────────────────────────────────────────────────

/// Surface en relief (`neu` / `neu-sm`).
class NeuBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool small;
  final Color? color;
  final VoidCallback? onTap;

  const NeuBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.small = false,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: small ? AppColors.neuShadowSm : AppColors.neuShadow,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return PressScale(onTap: onTap!, child: box);
  }
}

/// Surface en creux (`neu-inset`) : champs, segments actifs, pastilles.
class NeuInset extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const NeuInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(
        painter: _InnerShadowPainter(radius: radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Ombre intérieure (Flutter n'a pas de `BoxShadow` inset) : ombre sombre en
/// haut à gauche, reflet clair en bas à droite, comme `--shadow-neu-inset`.
class _InnerShadowPainter extends CustomPainter {
  final double radius;

  const _InnerShadowPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);
    for (final (color, offset) in const [
      (AppColors.neuDark, Offset(4, 4)),
      (AppColors.neuLight, Offset(-4, -4)),
    ]) {
      final paint = Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rrect.outerRect.inflate(20))
        ..addRRect(rrect.shift(offset));
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) => old.radius != radius;
}

/// Panneau en verre (`glass` / `glass-dark`) : flou d'arrière-plan,
/// translucide, liseré clair.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Variante posée sur le dégradé de marque (en-têtes, splash).
  final bool onBrand;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 28,
    this.onBrand = false,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: onBrand ? null : AppColors.neuShadowSm,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: shape,
              color: onBrand
                  ? AppColors.onPrimary.withValues(alpha: 0.18)
                  : AppColors.surface.withValues(alpha: 0.72),
              border: Border.all(
                color: onBrand
                    ? AppColors.onPrimary.withValues(alpha: 0.35)
                    : AppColors.surface.withValues(alpha: 0.85),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── Boutons ───────────────────────────────────────────────────────────────

/// Léger enfoncement au toucher (`active:scale-[0.98]`).
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const PressScale({super.key, required this.child, required this.onTap});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// Bouton principal à dégradé avec halo (`btn-brand`).
class GlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? leadingIcon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool expanded;
  final EdgeInsetsGeometry padding;

  const GlowButton({
    super.key,
    required this.label,
    this.icon,
    this.leadingIcon,
    this.onPressed,
    this.isLoading = false,
    this.expanded = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
          )
        else ...[
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 20, color: AppColors.onPrimary),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.buttonLarge.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 8),
            Icon(icon, size: 20, color: AppColors.onPrimary),
          ],
        ],
      ],
    );
    final button = AnimatedOpacity(
      opacity: enabled || isLoading ? 1 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: AppColors.ctaGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled ? AppColors.ctaShadow : null,
        ),
        child: content,
      ),
    );
    if (!enabled) return button;
    return PressScale(onTap: onPressed!, child: button);
  }
}

/// Bouton secondaire en relief (texte coloré sur surface `neu`).
class NeuButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;

  const NeuButton({super.key, required this.label, this.icon, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.primary;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: NeuBox(
        small: true,
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        onTap: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.buttonLarge.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton rond en verre sur l'en-tête (retour, cloche…).
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool showDot;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = PressScale(
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          children: [
            Positioned.fill(
              child: GlassPanel(
                onBrand: true,
                radius: 22,
                padding: EdgeInsets.zero,
                child: Center(child: Icon(icon, size: 21, color: AppColors.onPrimary)),
              ),
            ),
            if (showDot)
              Positioned(
                right: 9,
                top: 9,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

// ─── En-tête de marque ─────────────────────────────────────────────────────

/// En-tête en dégradé aux coins inférieurs arrondis, avec une bulle de verre
/// décorative. Le contenu de l'écran vient le chevaucher : placer l'écran
/// dans un [BrandHeaderLayout].
class BrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// Contenu sous le titre (segmenté, recherche…), toujours sur le dégradé.
  final Widget? bottom;

  /// Espace laissé sous l'en-tête pour le chevauchement du contenu.
  final double overlap;

  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.bottom,
    this.overlap = 56,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Opacity(
              opacity: 0.6,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.onPrimary.withValues(alpha: 0.16),
                  border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 16, 20, overlap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (onBack != null) ...[
                      GlassIconButton(icon: Icons.arrow_back_rounded, onPressed: onBack!, tooltip: 'Retour'),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.title1.copyWith(color: AppColors.onPrimary, fontSize: 24),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.onPrimary.withValues(alpha: 0.85),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                if (bottom != null) ...[
                  const SizedBox(height: 20),
                  bottom!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Page à en-tête de marque dont le contenu remonte sur l'en-tête
/// (`-mt-10` du template).
class BrandHeaderLayout extends StatelessWidget {
  final BrandHeader header;
  final List<Widget> children;
  final double overlap;
  final EdgeInsetsGeometry padding;
  final Future<void> Function()? onRefresh;
  final double bottomSpacing;

  const BrandHeaderLayout({
    super.key,
    required this.header,
    required this.children,
    this.overlap = 40,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.onRefresh,
    this.bottomSpacing = 32,
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        header,
        Transform.translate(
          offset: Offset(0, -overlap),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        SizedBox(height: bottomSpacing - overlap > 0 ? bottomSpacing - overlap : 0),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(color: AppColors.primary, onRefresh: onRefresh!, child: list);
  }
}

// ─── Contrôles ─────────────────────────────────────────────────────────────

/// Contrôle segmenté : pastille active en relief, piste en creux (ou en
/// verre sur le dégradé).
class GlowSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool onBrand;

  const GlowSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.onBrand = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        for (final (v, label) in options)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: v == value ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: v == value
                      ? const [BoxShadow(color: Color(0x2207232F), blurRadius: 8, offset: Offset(0, 3))]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: AppTextStyles.bodySemibold.copyWith(
                    color: v == value
                        ? AppColors.primary
                        : onBrand
                            ? AppColors.onPrimary
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return onBrand
        ? GlassPanel(onBrand: true, radius: 17, padding: const EdgeInsets.all(4), child: row)
        : NeuInset(radius: 17, padding: const EdgeInsets.all(4), child: row);
  }
}

/// Avatar à initiales sur le dégradé de marque, cerclé de blanc.
class BrandAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;

  const BrandAvatar({super.key, required this.name, this.size = 44, this.imageUrl});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.brandGradient,
        border: Border.all(color: AppColors.surface, width: size > 60 ? 4 : 3),
        boxShadow: const [BoxShadow(color: Color(0x2607232F), blurRadius: 10, offset: Offset(0, 4))],
        image: imageUrl != null && imageUrl!.isNotEmpty
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? null
          : Text(
              _initials,
              style: AppTextStyles.bodySemibold.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.34,
              ),
            ),
    );
  }
}

/// Pastille « secondary » du template (places, heure…).
class GlowPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;

  const GlowPill({super.key, required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? const Color(0xFF00353E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: AppTextStyles.caption.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─── Animations ────────────────────────────────────────────────────────────

/// Apparition qui monte en fondu (`animate-rise`), avec délai optionnel.
class RiseIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.offset = 18,
  });

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: const Cubic(0.22, 1, 0.36, 1));
  Timer? _start;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _start = Timer(widget.delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - _t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Flottement vertical continu (`animate-float`).
class FloatingMotion extends StatefulWidget {
  final Widget child;
  final double amplitude;

  const FloatingMotion({super.key, required this.child, this.amplitude = 8});

  @override
  State<FloatingMotion> createState() => _FloatingMotionState();
}

class _FloatingMotionState extends State<FloatingMotion> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        // 0 → -amplitude → 0, en douceur.
        final y = -widget.amplitude * (0.5 - 0.5 * math.cos(_c.value * 2 * math.pi));
        return Transform.translate(offset: Offset(0, y), child: child);
      },
      child: widget.child,
    );
  }
}

/// Anneau qui s'agrandit et s'efface en boucle (`animate-ring-pulse`).
class PulseRing extends StatefulWidget {
  final double size;
  final double radius;

  const PulseRing({super.key, required this.size, this.radius = 32});

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOut.transform(_c.value);
        return Transform.scale(
          scale: 0.8 + t,
          child: Opacity(
            opacity: 0.6 * (1 - t),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                color: AppColors.onPrimary.withValues(alpha: 0.18),
                border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.35)),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Barre d'app de marque ─────────────────────────────────────────────────

/// Barre d'app en dégradé aux coins inférieurs arrondis, pour les écrans
/// dont le contenu ne chevauche pas l'en-tête (formulaires, listes à
/// onglets). Bouton retour en verre ; [bottom] accueille un segmenté.
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;

  /// `null` : pas de bouton retour (onglets principaux).
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? bottom;
  final double bottomHeight;

  const BrandAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.bottom,
    this.bottomHeight = 0,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(78 + (subtitle != null ? 18 : 0) + (bottom != null ? bottomHeight + 16 : 0));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (onBack != null) ...[
                    GlassIconButton(icon: Icons.arrow_back_rounded, onPressed: onBack!, tooltip: 'Retour'),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.title1.copyWith(color: AppColors.onPrimary, fontSize: 22),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85)),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 16),
                SizedBox(height: bottomHeight, child: bottom),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Action textuelle pour [BrandAppBar] (« Tout lire »…).
class BrandAppBarTextAction extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const BrandAppBarTextAction({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: AppTextStyles.bodySemibold.copyWith(color: AppColors.onPrimary)),
    );
  }
}

/// Barre d'action fixe en bas d'écran (prix + bouton), pleine largeur,
/// même traitement que la barre de navigation.
class BottomActionBar extends StatelessWidget {
  final Widget child;

  const BottomActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Color(0x1407232F), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
          child: child,
        ),
      ),
    );
  }
}
