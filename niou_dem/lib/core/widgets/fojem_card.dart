import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class FojemCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final bool hasShadow;

  const FojemCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderRadius,
    this.hasShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ??
        BorderRadius.circular(AppSpacing.borderRadiusMd);

    return Material(
      color: backgroundColor ?? AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: AppColors.primary.withOpacity(0.04),
        highlightColor: AppColors.primary.withOpacity(0.02),
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.surface,
            borderRadius: radius,
            boxShadow: hasShadow
                ? [
                    BoxShadow(
                      color: const Color(0xFF000000).withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: const Color(0xFF000000).withOpacity(0.04),
                      blurRadius: 1,
                      offset: const Offset(0, 0),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: padding ?? AppSpacing.cardPadding,
            child: child,
          ),
        ),
      ),
    );
  }
}
