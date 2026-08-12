import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../theme/app_theme.dart';

/// Bottom sheet shown when tapping a product tile that has sizes
/// (Product.hasVariants) instead of adding straight to the cart.
/// Tapping a row calls [onSelected] with the chosen variant and closes
/// the sheet. Products without variants never trigger this — see
/// RegisterScreen's product-tap handler.
class ProductSizePickerSheet extends StatelessWidget {
  final Product product;
  final ValueChanged<ProductVariant> onSelected;

  const ProductSizePickerSheet({
    super.key,
    required this.product,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required Product product,
    required ValueChanged<ProductVariant> onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.slate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ProductSizePickerSheet(product: product, onSelected: onSelected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              product.name.toUpperCase(),
              style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.2),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a size',
              style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            ...product.variants.map((variant) => InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(variant);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(variant.name, style: AppTextStyles.body(size: 15, weight: FontWeight.w600)),
                        ),
                        Text(
                          '₱${variant.price.toStringAsFixed(2)}',
                          style: AppTextStyles.mono(size: 15, weight: FontWeight.w700, color: AppColors.ledAmber),
                        ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
