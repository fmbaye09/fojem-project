import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

enum FojemButtonVariant { primary, secondary, ghost, danger, dangerOutline }
enum FojemButtonSize { large, medium, small }

class FojemButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final FojemButtonVariant variant;
  final FojemButtonSize size;
  final bool isLoading;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final bool fullWidth;

  const FojemButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FojemButtonVariant.primary,
    this.size = FojemButtonSize.large,
    this.isLoading = false,
    this.prefixIcon,
    this.suffixIcon,
    this.fullWidth = true,
  });

  const FojemButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = FojemButtonSize.large,
    this.isLoading = false,
    this.prefixIcon,
    this.suffixIcon,
    this.fullWidth = true,
  }) : variant = FojemButtonVariant.primary;

  const FojemButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = FojemButtonSize.large,
    this.isLoading = false,
    this.prefixIcon,
    this.suffixIcon,
    this.fullWidth = true,
  }) : variant = FojemButtonVariant.secondary;

  const FojemButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.size = FojemButtonSize.large,
    this.isLoading = false,
    this.prefixIcon,
    this.suffixIcon,
    this.fullWidth = true,
  }) : variant = FojemButtonVariant.ghost;

  const FojemButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.size = FojemButtonSize.large,
    this.isLoading = false,
    this.prefixIcon,
    this.suffixIcon,
    this.fullWidth = true,
  }) : variant = FojemButtonVariant.danger;

  /// Bordure + texte rouge sur fond blanc — ex. "Refuser" une demande.
  const FojemButton.dangerOutline({
    super.key,
    required this.label,
    this.onPressed,
    this.size = FojemButtonSize.large,
    this.isLoading = false,
    this.prefixIcon,
    this.suffixIcon,
    this.fullWidth = true,
  }) : variant = FojemButtonVariant.dangerOutline;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null && !isLoading;
    final height = _height;
    final textStyle = size == FojemButtonSize.small
        ? AppTextStyles.buttonSmall
        : AppTextStyles.buttonLarge;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: _buildButton(isDisabled, textStyle),
    );
  }

  Widget _buildButton(bool isDisabled, TextStyle textStyle) {
    switch (variant) {
      case FojemButtonVariant.primary:
        return _PrimaryButton(
          label: label,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
          isDisabled: isDisabled,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          textStyle: textStyle,
          height: _height,
          iconSize: _iconSize,
        );
      case FojemButtonVariant.secondary:
        return _SecondaryButton(
          label: label,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
          isDisabled: isDisabled,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          textStyle: textStyle,
          height: _height,
          iconSize: _iconSize,
        );
      case FojemButtonVariant.ghost:
        return _GhostButton(
          label: label,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
          isDisabled: isDisabled,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          textStyle: textStyle,
          height: _height,
          iconSize: _iconSize,
        );
      case FojemButtonVariant.danger:
        return _DangerButton(
          label: label,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
          isDisabled: isDisabled,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          textStyle: textStyle,
          height: _height,
          iconSize: _iconSize,
        );
      case FojemButtonVariant.dangerOutline:
        return _DangerOutlineButton(
          label: label,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
          isDisabled: isDisabled,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          textStyle: textStyle,
          height: _height,
          iconSize: _iconSize,
        );
    }
  }

  double get _height {
    switch (size) {
      case FojemButtonSize.large:
        return 52;
      case FojemButtonSize.medium:
        return 44;
      case FojemButtonSize.small:
        return 36;
    }
  }

  double get _iconSize {
    switch (size) {
      case FojemButtonSize.large:
        return 20;
      case FojemButtonSize.medium:
        return 18;
      case FojemButtonSize.small:
        return 16;
    }
  }
}

class _ButtonContent extends StatelessWidget {
  final String label;
  final bool isLoading;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final TextStyle textStyle;
  final Color contentColor;
  final double iconSize;

  const _ButtonContent({
    required this.label,
    required this.isLoading,
    required this.textStyle,
    required this.contentColor,
    required this.iconSize,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(contentColor),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (prefixIcon != null) ...[
          Icon(prefixIcon, size: iconSize, color: contentColor),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            style: textStyle.copyWith(color: contentColor),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (suffixIcon != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Icon(suffixIcon, size: iconSize, color: contentColor),
        ],
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final TextStyle textStyle;
  final double height;
  final double iconSize;

  const _PrimaryButton({
    required this.label,
    this.onPressed,
    required this.isLoading,
    required this.isDisabled,
    required this.textStyle,
    required this.height,
    required this.iconSize,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDisabled
        ? AppColors.primary.withOpacity(0.4)
        : AppColors.primary;
    const contentColor = Colors.white;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        splashColor: Colors.white.withOpacity(0.1),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            child: _ButtonContent(
              label: label,
              isLoading: isLoading,
              textStyle: textStyle,
              contentColor: contentColor,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              iconSize: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final TextStyle textStyle;
  final double height;
  final double iconSize;

  const _SecondaryButton({
    required this.label,
    this.onPressed,
    required this.isLoading,
    required this.isDisabled,
    required this.textStyle,
    required this.height,
    required this.iconSize,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDisabled ? AppColors.border : AppColors.primary;
    final contentColor =
        isDisabled ? AppColors.textMuted : AppColors.primary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        splashColor: AppColors.primary.withOpacity(0.06),
        highlightColor: AppColors.primary.withOpacity(0.04),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          ),
          child: Center(
            child: _ButtonContent(
              label: label,
              isLoading: isLoading,
              textStyle: textStyle,
              contentColor: contentColor,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              iconSize: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final TextStyle textStyle;
  final double height;
  final double iconSize;

  const _GhostButton({
    required this.label,
    this.onPressed,
    required this.isLoading,
    required this.isDisabled,
    required this.textStyle,
    required this.height,
    required this.iconSize,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final contentColor =
        isDisabled ? AppColors.textMuted : AppColors.primary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        splashColor: AppColors.primary.withOpacity(0.06),
        highlightColor: AppColors.primary.withOpacity(0.04),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            child: _ButtonContent(
              label: label,
              isLoading: isLoading,
              textStyle: textStyle,
              contentColor: contentColor,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              iconSize: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _DangerOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final TextStyle textStyle;
  final double height;
  final double iconSize;

  const _DangerOutlineButton({
    required this.label,
    this.onPressed,
    required this.isLoading,
    required this.isDisabled,
    required this.textStyle,
    required this.height,
    required this.iconSize,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDisabled ? AppColors.border : AppColors.danger;
    final contentColor = isDisabled ? AppColors.textMuted : AppColors.danger;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        splashColor: AppColors.danger.withOpacity(0.06),
        highlightColor: AppColors.danger.withOpacity(0.04),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          ),
          child: Center(
            child: _ButtonContent(
              label: label,
              isLoading: isLoading,
              textStyle: textStyle,
              contentColor: contentColor,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              iconSize: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final TextStyle textStyle;
  final double height;
  final double iconSize;

  const _DangerButton({
    required this.label,
    this.onPressed,
    required this.isLoading,
    required this.isDisabled,
    required this.textStyle,
    required this.height,
    required this.iconSize,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDisabled ? AppColors.border : AppColors.danger;
    final contentColor = isDisabled ? AppColors.textMuted : Colors.white;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
        splashColor: Colors.white.withOpacity(0.1),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            child: _ButtonContent(
              label: label,
              isLoading: isLoading,
              textStyle: textStyle,
              contentColor: contentColor,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              iconSize: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
