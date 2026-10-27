import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class PriceDisplay extends StatelessWidget {
  final double amount;
  final bool isLarge;
  final bool showCurrency;
  final Color? color;
  final TextStyle? customStyle;

  const PriceDisplay({
    super.key,
    required this.amount,
    this.isLarge = false,
    this.showCurrency = true,
    this.color,
    this.customStyle,
  });

  static final _formatter = NumberFormat('#,###', 'fr_FR');

  static String formatAmount(double amount) {
    return _formatter.format(amount.toInt()).replaceAll(',', ' ');
  }

  String get _formattedAmount => formatAmount(amount);

  @override
  Widget build(BuildContext context) {
    final style = customStyle ??
        (isLarge ? AppTextStyles.priceLarge : AppTextStyles.price);
    final textColor = color ?? AppColors.primary;

    if (!showCurrency) {
      return Text(
        _formattedAmount,
        style: style.copyWith(color: textColor),
      );
    }

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: _formattedAmount,
            style: style.copyWith(color: textColor),
          ),
          TextSpan(
            text: ' FCFA',
            style: style.copyWith(
              color: textColor,
              fontSize: (style.fontSize ?? 18) * 0.7,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
