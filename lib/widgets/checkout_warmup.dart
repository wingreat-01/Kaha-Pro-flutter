import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'led_total.dart';

/// Pre-warms whatever CheckoutModal pays for on its first-ever open —
/// mainly IBM Plex Mono glyph rasterization for LedTotal's big amber
/// total/change readouts, plus the rounded-container/border paint path
/// the modal reuses. That cost is normally invisible except the very
/// first time it happens in a session, which is what showed up as a
/// slow/glitchy first checkout.
///
/// Mount this once, low in the tree (see HomeShell), so the cost gets
/// paid quietly right after login instead of during a cashier's first
/// real sale. It paints for exactly one frame — invisible (0 opacity,
/// clipped to 1x1px, ignores touches) — then unmounts itself; it only
/// needs to be painted once to prime the engine's caches, not kept
/// around.
class CheckoutWarmup extends StatefulWidget {
  const CheckoutWarmup({super.key});

  @override
  State<CheckoutWarmup> createState() => _CheckoutWarmupState();
}

class _CheckoutWarmupState extends State<CheckoutWarmup> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Let the widget actually paint once (opacity 0 still paints, unlike
    // Offstage/Visibility(visible: false), which skip painting entirely
    // and wouldn't warm anything) before removing it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      top: 0,
      child: IgnorePointer(
        child: ClipRect(
          child: SizedBox(
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.slate,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.slateBorder, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LedTotal(amount: 0, label: 'TOTAL DUE'),
                    const LedTotal(
                      amount: 0,
                      label: 'CHANGE',
                      fontSize: 26,
                      color: AppColors.tillGreen,
                    ),
                    // Same glyph set the cash-tendered field and quick
                    // chips render — digits, peso sign, decimal point.
                    Text(
                      '₱0123456789.00',
                      style: AppTextStyles.mono(size: 22, weight: FontWeight.w700, color: AppColors.ledAmber),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
