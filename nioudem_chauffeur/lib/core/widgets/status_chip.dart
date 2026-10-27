import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

enum StatusChipVariant { confirmed, pending, refused, cancelled, completed, online, offline }

class StatusChip extends StatelessWidget {
  final StatusChipVariant variant;
  final String? customLabel;

  const StatusChip({
    super.key,
    required this.variant,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            customLabel ?? _label,
            style: AppTextStyles.label.copyWith(
              color: _textColor,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color get _backgroundColor {
    switch (variant) {
      case StatusChipVariant.confirmed:
        return AppColors.successSurface;
      case StatusChipVariant.pending:
        return AppColors.primarySurface;
      case StatusChipVariant.refused:
        return AppColors.dangerSurface;
      case StatusChipVariant.cancelled:
        return AppColors.dangerSurface;
      case StatusChipVariant.completed:
        return AppColors.background;
      case StatusChipVariant.online:
        return AppColors.successSurface;
      case StatusChipVariant.offline:
        return AppColors.background;
    }
  }

  Color get _textColor {
    switch (variant) {
      case StatusChipVariant.confirmed:
        return AppColors.success;
      case StatusChipVariant.pending:
        return AppColors.primary;
      case StatusChipVariant.refused:
        return AppColors.danger;
      case StatusChipVariant.cancelled:
        return AppColors.danger;
      case StatusChipVariant.completed:
        return AppColors.textSecondary;
      case StatusChipVariant.online:
        return AppColors.success;
      case StatusChipVariant.offline:
        return AppColors.textMuted;
    }
  }

  Color get _dotColor => _textColor;

  String get _label {
    switch (variant) {
      case StatusChipVariant.confirmed:
        return 'Confirmé';
      case StatusChipVariant.pending:
        return 'En attente';
      case StatusChipVariant.refused:
        return 'Refusé';
      case StatusChipVariant.cancelled:
        return 'Annulé';
      case StatusChipVariant.completed:
        return 'Terminé';
      case StatusChipVariant.online:
        return 'En ligne';
      case StatusChipVariant.offline:
        return 'Hors ligne';
    }
  }
}
