import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class StarRating extends StatelessWidget {
  final double rating;
  final int maxStars;
  final double size;
  final bool showLabel;
  final int? reviewCount;

  const StarRating({
    super.key,
    required this.rating,
    this.maxStars = 5,
    this.size = 16,
    this.showLabel = true,
    this.reviewCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(maxStars, (index) {
          final filled = index < rating.floor();
          final partial = !filled && index < rating;

          return Padding(
            padding: EdgeInsets.only(right: size * 0.1),
            child: Icon(
              partial
                  ? Icons.star_half_rounded
                  : filled
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
              size: size,
              color: filled || partial
                  ? AppColors.success
                  : AppColors.border,
            ),
          );
        }),
        if (showLabel) ...[
          SizedBox(width: size * 0.25),
          Text(
            rating.toStringAsFixed(1),
            style: AppTextStyles.bodySemibold.copyWith(
              fontSize: size * 0.875,
              color: AppColors.textPrimary,
            ),
          ),
          if (reviewCount != null) ...[
            const SizedBox(width: 2),
            Text(
              '($reviewCount)',
              style: AppTextStyles.caption.copyWith(
                fontSize: size * 0.75,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class InteractiveStarRating extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double> onRatingChanged;
  final double size;

  const InteractiveStarRating({
    super.key,
    this.initialRating = 0,
    required this.onRatingChanged,
    this.size = 40,
  });

  @override
  State<InteractiveStarRating> createState() =>
      _InteractiveStarRatingState();
}

class _InteractiveStarRatingState extends State<InteractiveStarRating> {
  late double _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starValue = (index + 1).toDouble();
        return GestureDetector(
          onTap: () {
            setState(() => _rating = starValue);
            widget.onRatingChanged(starValue);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.all(widget.size * 0.1),
            child: Icon(
              _rating >= starValue
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: widget.size,
              color: _rating >= starValue
                  ? AppColors.accent
                  : AppColors.border,
            ),
          ),
        );
      }),
    );
  }
}
