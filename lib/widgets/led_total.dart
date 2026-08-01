import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The signature "calculator screen" element: glowing amber digits
/// on the dark register body. Used in the cart panel and (later)
/// the checkout modal.
class LedTotal extends StatelessWidget {
  final double amount;
  final String label;
  final double fontSize;
  final Color? color;

  const LedTotal({
    super.key,
    required this.amount,
    this.label = 'TOTAL',
    this.fontSize = 32,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = color ?? AppColors.ledAmber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.slateField,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: AppTextStyles.mono(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: AppTextStyles.mono(
              size: fontSize,
              weight: FontWeight.w700,
              color: displayColor,
            ).copyWith(
              shadows: [
                Shadow(color: displayColor.withOpacity(0.65), blurRadius: 16),
                Shadow(color: displayColor.withOpacity(0.35), blurRadius: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
