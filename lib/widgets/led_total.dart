import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The signature "calculator screen" element: glowing amber digits
/// on the dark register body. Used in the cart panel (checkout modal /
/// transaction detail still use the static, non-animated render for now).
///
/// Digits roll like an odometer when [amount] changes — each digit slides
/// in from below and the old one slides out above when the total goes up,
/// and the reverse when it goes down. Only characters that actually
/// changed value animate; unchanged digits, the peso sign, and the
/// decimal point stay put.
///
/// Known limitation: roll direction is a single "total went up or down"
/// call applied to every digit, not a true per-digit magnitude compare —
/// and if the number of characters changes (e.g. 99.99 -> 100.00 adds a
/// digit), the position-based keys can momentarily misalign since digits
/// are indexed left-to-right rather than diffed from the right. Fine for
/// typical cart totals; worth revisiting if that turns out to look off.
class LedTotal extends StatefulWidget {
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
  State<LedTotal> createState() => _LedTotalState();
}

class _LedTotalState extends State<LedTotal> {
  double? _previousAmount;

  @override
  void didUpdateWidget(covariant LedTotal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amount != widget.amount) {
      _previousAmount = oldWidget.amount;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayColor = widget.color ?? AppColors.ledAmber;
    final text = '₱${widget.amount.toStringAsFixed(2)}';

    // null = don't know direction yet (first build) -> render statically.
    final bool? rollingUp =
        _previousAmount == null ? null : widget.amount > _previousAmount!;

    final style = AppTextStyles.mono(
      size: widget.fontSize,
      weight: FontWeight.w700,
      color: displayColor,
    ).copyWith(
      shadows: [
        Shadow(color: displayColor.withOpacity(0.65), blurRadius: 16),
        Shadow(color: displayColor.withOpacity(0.35), blurRadius: 32),
      ],
    );

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
            widget.label,
            style: AppTextStyles.mono(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < text.length; i++)
                _OdometerChar(
                  key: ValueKey(i),
                  char: text[i],
                  style: style,
                  rollingUp: rollingUp,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OdometerChar extends StatelessWidget {
  static final _digitPattern = RegExp(r'[0-9]');

  final String char;
  final TextStyle style;
  final bool? rollingUp;

  const _OdometerChar({
    super.key,
    required this.char,
    required this.style,
    required this.rollingUp,
  });

  @override
  Widget build(BuildContext context) {
    final isDigit = _digitPattern.hasMatch(char);

    // Non-digits (₱, .) and the very first render (no known direction
    // yet) just render as plain text — nothing to roll.
    if (!isDigit || rollingUp == null) {
      return Text(char, style: style);
    }

    final currentKey = ValueKey(char);

    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final incoming = child.key == currentKey;
          final beginY = incoming
              ? (rollingUp! ? 1.0 : -1.0) // enters from below (up) / above (down)
              : (rollingUp! ? -1.0 : 1.0); // exits upward (up) / downward (down)
          final offsetAnimation = Tween<Offset>(
            begin: Offset(0, beginY),
            end: Offset.zero,
          ).animate(animation);
          return ClipRect(
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
        child: Text(char, key: currentKey, style: style),
      ),
    );
  }
}
