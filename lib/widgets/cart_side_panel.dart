import 'package:flutter/material.dart';
import '../state/cart_provider.dart';
import '../theme/app_theme.dart';
import 'cart_list.dart';
import 'led_total.dart';

/// Cart panel shown alongside the product grid on wide (tablet/web) layouts.
class CartSidePanel extends StatelessWidget {
  final CartProvider cart;
  final VoidCallback onCheckout;

  const CartSidePanel({super.key, required this.cart, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.slate,
        border: Border(left: BorderSide(color: AppColors.slateBorder, width: 1)),
      ),
      child: Column(
        children: [
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
                    onPressed: cart.isEmpty ? null : onCheckout,
                    child: const Text('Checkout'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
