import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

class FojemSearchBar extends StatelessWidget {
  final String? hint;
  final String? departure;
  final String? arrival;
  final VoidCallback onTap;

  const FojemSearchBar({
    super.key,
    this.hint,
    this.departure,
    this.arrival,
    required this.onTap,
  });

  bool get _hasSearch => departure != null || arrival != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.primary, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _hasSearch
                  ? _SearchPreview(
                      departure: departure!,
                      arrival: arrival,
                    )
                  : Text(
                      hint ?? 'Où allez-vous ?',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
            ),
            if (_hasSearch)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.tune,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchPreview extends StatelessWidget {
  final String departure;
  final String? arrival;

  const _SearchPreview({required this.departure, this.arrival});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          departure,
          style: AppTextStyles.bodySemibold,
        ),
        if (arrival != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Icon(
              Icons.arrow_forward,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            arrival!,
            style: AppTextStyles.bodySemibold,
          ),
        ],
      ],
    );
  }
}
