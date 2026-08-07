import 'package:flutter/material.dart';
import '../state/cart_provider.dart';
import '../theme/app_theme.dart';
import 'cart_list.dart';
import 'led_total.dart';

/// Collapsed bar pinned to the bottom on phone widths, showing item
/// count + running total. Tapping expands the full cart in a modal sheet.
class CartBottomBar extends StatelessWidget {
  final CartProvider cart;
  final VoidCallback onCheckout;

  const CartBottomBar({super.key, required this.cart, required this.onCheckout});

  void _expand(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return ListenableBuilder(
              listenable: cart,
              builder: (context, _) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.slate,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.slateBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Text('CURRENT ORDER',
                                style: AppTextStyles.mono(
                                    size: 12, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.5)),
                            const Spacer(),
                            if (!cart.isEmpty)
                              TextButton(
                                onPressed: cart.clear,
                                child: Text('Clear', style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: CartList(cart: cart),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            LedTotal(amount: cart.total),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                        onCheckout();
                                      },
                                child: const Text('Checkout'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _expand(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.slate,
          border: Border(top: BorderSide(color: AppColors.slateBorder, width: 1)),
        ),
        child: Row(
          children: [
            Icon(Icons.shopping_bag_outlined, color: AppColors.ledAmber, size: 24),
            const SizedBox(width: 10),
            Text(
              '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
              style: AppTextStyles.body(size: 15, weight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const Spacer(),
            Text(
              '₱${cart.total.toStringAsFixed(2)}',
              style: AppTextStyles.mono(size: 19, weight: FontWeight.w700, color: AppColors.ledAmber),
            ),
            const SizedBox(width: 8),
            Icon(Icons.keyboard_arrow_up, color: AppColors.textMuted, size: 24),
          ],
        ),
      ),
    );
  }
}
