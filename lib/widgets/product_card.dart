import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';

/// A single product "key" in the register grid.
/// Depresses on tap like a real register/calculator button.
/// In edit mode, shows a delete X badge instead of responding to tap-to-add.
class ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;
  final bool isEditMode;
  final VoidCallback? onDelete;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.isEditMode = false,
    this.onDelete,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTapDown: widget.isEditMode ? null : (_) => setState(() => _pressed = true),
          onTapUp: widget.isEditMode ? null : (_) => setState(() => _pressed = false),
          onTapCancel: widget.isEditMode ? null : () => setState(() => _pressed = false),
          onTap: widget.isEditMode ? null : widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(
                color: AppColors.slate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isEditMode
                      ? AppColors.ledgerRed.withOpacity(0.4)
                      : (_pressed ? AppColors.ledAmber : Colors.black.withOpacity(0.3)),
                  width: 1.5,
                ),
                boxShadow: _pressed
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.emoji ?? '🛒',
                    style: const TextStyle(fontSize: 34),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 34, // fixed slot for up to 2 lines — keeps emoji/name/price
                                // aligned at the same height on every card, regardless
                                // of how long the product name is
                    child: Center(
                      child: Text(
                        product.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₱${product.price.toStringAsFixed(2)}',
                    style: AppTextStyles.mono(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.ledAmber,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.isEditMode)
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.ledgerRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.charcoal, width: 2),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 15),
              ),
            ),
          ),
      ],
    );
  }
}
