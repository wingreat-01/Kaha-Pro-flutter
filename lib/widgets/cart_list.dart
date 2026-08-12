import 'package:flutter/material.dart';
import '../state/cart_provider.dart';
import '../theme/app_theme.dart';

/// Scrollable list of cart line items with quantity steppers.
/// Reused inside the wide-screen side panel and the phone bottom sheet.
class CartList extends StatelessWidget {
  final CartProvider cart;

  const CartList({super.key, required this.cart});

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'Cart is empty',
            style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cart.items.length,
      separatorBuilder: (_, __) => Divider(color: AppColors.slateBorder, height: 20),
      itemBuilder: (context, index) {
        final item = cart.items[index];
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    style: AppTextStyles.body(size: 13.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₱${item.unitPrice.toStringAsFixed(2)} each',
                    style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            _QtyStepper(
              quantity: item.quantity,
              onDecrement: () => cart.decrement(item.product.id, variantId: item.selectedVariant?.id),
              onIncrement: () => cart.increment(item.product.id, variantId: item.selectedVariant?.id),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(
                '₱${item.lineTotal.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber),
              ),
            ),
            _RemoveButton(onTap: () => cart.remove(item.product.id, variantId: item.selectedVariant?.id)),
          ],
        );
      },
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RemoveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Icon(Icons.close, size: 16, color: AppColors.textMuted),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QtyStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slateField,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.slateBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(icon: Icons.remove, onTap: onDecrement),
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: AppTextStyles.mono(size: 13, weight: FontWeight.w700),
            ),
          ),
          _StepperButton(icon: Icons.add, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 15, color: AppColors.ledAmber),
      ),
    );
  }
}
