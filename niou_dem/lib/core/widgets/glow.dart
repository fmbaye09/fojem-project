import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Kit d'interface FOJËM : surfaces blanches à bord fin, champs gris pleins,
/// un bouton principal dans la couleur de la marque, en-têtes clairs à grand
/// titre. Les noms viennent de l'ancien style « Glow Flow » (néomorphisme) ;
/// ils sont gardés pour que les écrans n'aient pas à changer.

/// Animations réduites demandées par le système (accessibilité).
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ─── Surfaces ──────────────────────────────────────────────────────────────

/// Carte blanche à bord fin ; touchable si [onTap] est fourni (ondulation).
class NeuBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Sans ombre (carte posée dans une autre carte).
  final bool small;
  final Color? color;
  final VoidCallback? onTap;

  const NeuBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.small = false,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final plain = color == null || color == AppColors.surface;
    final decoration = BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: shape,
      border: plain ? Border.all(color: AppColors.border) : null,
      boxShadow: plain && !small ? AppColors.neuShadowSm : null,
    );
    if (onTap == null) {
      return Container(padding: padding, decoration: decoration, child: child);
    }
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Zone grise pleine : champs, pastilles, contenu mis en retrait.
class NeuInset extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const NeuInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// Panneau principal d'un écran (carte blanche) ; [onBrand] : variante
/// translucide, pour un panneau posé sur un fond sombre (écran de démarrage).
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool onBrand;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.onBrand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: onBrand ? Colors.white.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: onBrand ? Colors.white.withValues(alpha: 0.24) : AppColors.border),
        boxShadow: onBrand ? null : AppColors.neuShadowSm,
      ),
      child: child,
    );
  }
}

// ─── Boutons ───────────────────────────────────────────────────────────────

/// Retour visuel au toucher pour un contenu sans ondulation possible.
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
      child: AnimatedOpacity(
        opacity: _down ? 0.7 : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

/// Bouton principal : fond plein de la couleur de la marque, une seule fois
/// par écran. Désactivé, il passe au gris (et non en transparence).
class GlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? leadingIcon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool expanded;
  final EdgeInsetsGeometry padding;

  /// Variante sombre (bleu nuit) pour une action forte qui n'est pas
  /// l'action principale de l'écran.
  final bool dark;

  const GlowButton({
    super.key,
    required this.label,
    this.icon,
    this.leadingIcon,
    this.onPressed,
    this.isLoading = false,
    this.expanded = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final bg = !enabled && !isLoading
        ? AppColors.muted
        : dark
            ? AppColors.ink
            : AppColors.brand;
    final fg = !enabled && !isLoading
        ? AppColors.textMuted
        : dark
            ? Colors.white
            : AppColors.onBrand;
    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        else ...[
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 20, color: fg),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.buttonLarge.copyWith(color: fg),
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 8),
            Icon(icon, size: 20, color: fg),
          ],
        ],
      ],
    );
    final shape = BorderRadius.circular(14);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: bg,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          onTap: enabled ? onPressed : null,
          child: Padding(padding: padding, child: content),
        ),
      ),
    );
  }
}

/// Bouton secondaire : fond gris, texte bleu nuit (ou [color]).
class NeuButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;

  const NeuButton({super.key, required this.label, this.icon, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? (color ?? AppColors.textPrimary) : AppColors.textMuted;
    final shape = BorderRadius.circular(14);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: AppColors.muted,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    textAlign: TextAlign.center,
                    style: AppTextStyles.buttonLarge.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton rond (retour, cloche, fermer…) : blanc, bord fin, icône bleu nuit.
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
    final button = Semantics(
      button: true,
      label: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: AppColors.surface,
                shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPressed,
                  child: Center(child: Icon(icon, size: 22, color: AppColors.textPrimary)),
                ),
              ),
            ),
            if (showDot)
              Positioned(
                right: 11,
                top: 11,
                child: IgnorePointer(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
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

// ─── En-tête ───────────────────────────────────────────────────────────────

/// En-tête d'écran posé sur le fond : grand titre bleu nuit (écran
/// principal) ou titre courant avec bouton retour (écran ouvert depuis un
/// autre). À placer dans un [BrandHeaderLayout].
class BrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// Contenu sous le titre (segmenté, recherche…).
  final Widget? bottom;

  /// Hérité de l'ancien en-tête chevauché ; ignoré.
  final double overlap;

  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.bottom,
    this.overlap = 0,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final nested = onBack != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (nested) ...[
                GlassIconButton(icon: Icons.arrow_back_rounded, onPressed: onBack!, tooltip: 'Retour'),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: nested ? AppTextStyles.title2.copyWith(fontSize: 20) : AppTextStyles.display,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 16),
            bottom!,
          ],
        ],
      ),
    );
  }
}

/// Page à en-tête [BrandHeader] suivi du contenu, le tout défilant.
class BrandHeaderLayout extends StatelessWidget {
  final BrandHeader header;
  final List<Widget> children;

  /// Hérité de l'ancien en-tête chevauché ; ignoré.
  final double overlap;
  final EdgeInsetsGeometry padding;
  final Future<void> Function()? onRefresh;
  final double bottomSpacing;

  const BrandHeaderLayout({
    super.key,
    required this.header,
    required this.children,
    this.overlap = 0,
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
        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
        SizedBox(height: bottomSpacing),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(color: AppColors.ink, onRefresh: onRefresh!, child: list);
  }
}

// ─── Contrôles ─────────────────────────────────────────────────────────────

/// Contrôle segmenté : piste grise, option choisie en pastille blanche.
class GlowSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Hérité ; même rendu.
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: v == value ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: v == value
                          ? const [BoxShadow(color: Color(0x1A072945), blurRadius: 4, offset: Offset(0, 1))]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySemibold.copyWith(
                        color: v == value ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: v == value ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Avatar à initiales (ou photo) sur fond bleu pâle.
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
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primarySurface,
        image: hasImage ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: hasImage
          ? null
          : Text(
              _initials,
              style: AppTextStyles.bodySemibold.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.36,
              ),
            ),
    );
  }
}

/// Pastille d'information (places, heure…) : fond gris, texte bleu nuit.
class GlowPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;

  const GlowPill({super.key, required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.muted,
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

/// Apparition discrète (fondu + léger glissement), avec délai optionnel.
/// Désactivée quand le système demande moins d'animations.
class RiseIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 260),
    this.offset = 8,
  });

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _start;

  @override
  void initState() {
    super.initState();
    // Délai plafonné : une longue liste ne doit pas apparaître au compte-gouttes.
    final delay = widget.delay > const Duration(milliseconds: 240) ? const Duration(milliseconds: 240) : widget.delay;
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _start = Timer(delay, _c.forward);
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
    if (reduceMotion(context)) return widget.child;
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

/// Flottement vertical lent (illustrations), immobile si animations réduites.
class FloatingMotion extends StatefulWidget {
  final Widget child;
  final double amplitude;

  const FloatingMotion({super.key, required this.child, this.amplitude = 6});

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
    if (reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final y = -widget.amplitude * (0.5 - 0.5 * math.cos(_c.value * 2 * math.pi));
        return Transform.translate(offset: Offset(0, y), child: child);
      },
      child: widget.child,
    );
  }
}

/// Anneau qui s'agrandit et s'efface en boucle (attente, succès).
class PulseRing extends StatefulWidget {
  final double size;
  final double radius;
  final Color? color;

  const PulseRing({super.key, required this.size, this.radius = 32, this.color});

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
    if (reduceMotion(context)) return SizedBox(width: widget.size, height: widget.size);
    final color = widget.color ?? AppColors.brand;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOut.transform(_c.value);
        return Transform.scale(
          scale: 0.8 + t * 0.6,
          child: Opacity(
            opacity: 0.5 * (1 - t),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                color: color.withValues(alpha: 0.16),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Barre d'app ───────────────────────────────────────────────────────────

/// Barre d'app claire : grand titre sur un onglet principal, titre courant
/// et bouton retour sur un écran ouvert depuis un autre ; [bottom] accueille
/// un segmenté.
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
      Size.fromHeight(72 + (subtitle != null ? 20 : 0) + (bottom != null ? bottomHeight + 12 : 0));

  @override
  Widget build(BuildContext context) {
    final nested = onBack != null;
    return Material(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (nested) ...[
                    GlassIconButton(icon: Icons.arrow_back_rounded, onPressed: onBack!, tooltip: 'Retour'),
                    const SizedBox(width: 12),
                  ] else
                    const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nested ? AppTextStyles.title2.copyWith(fontSize: 20) : AppTextStyles.title1.copyWith(fontSize: 26),
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 12),
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
      child: Text(label, style: AppTextStyles.bodySemibold.copyWith(color: AppColors.textPrimary)),
    );
  }
}

/// Barre d'action fixe en bas d'écran (prix + bouton), au-dessus de la zone
/// de geste du système.
class BottomActionBar extends StatelessWidget {
  final Widget child;

  const BottomActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: child,
        ),
      ),
    );
  }
}
