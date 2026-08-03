import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/product_provider.dart';
import '../theme/app_theme.dart';

/// Real inventory list/add/edit panel — reached from Settings → Products.
/// Shows every product with its current stock, flags anything at or
/// below its own low-stock threshold, and lets you bump stock up/down
/// or restock/recount via a small dialog.
///
/// Stock lives on Product itself (stockQty, lowStockThreshold) rather
/// than a separate parallel list, so it can't drift out of sync with
/// the catalog the way category names once did between RegisterScreen
/// and ProductProvider.
class InventoryPanel extends StatelessWidget {
  const InventoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ProductProvider>();

    final byCategory = <String, List<Product>>{};
    for (final product in catalog.products) {
      byCategory.putIfAbsent(product.category, () => []).add(product);
    }
    final categories = byCategory.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        elevation: 0,
        title: Text(
          'Inventory',
          style: AppTextStyles.mono(size: 15, weight: FontWeight.w700, letterSpacing: 1),
        ),
      ),
      body: catalog.products.isEmpty
          ? Center(
              child: Text(
                'No products in the catalog yet.',
                style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final category in categories) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                    child: Text(
                      category.toUpperCase(),
                      style: AppTextStyles.mono(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.textMuted,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  for (final product in byCategory[category]!)
                    _InventoryRow(product: product, catalog: catalog),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  final Product product;
  final ProductProvider catalog;

  const _InventoryRow({required this.product, required this.catalog});

  void _openStockDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: product.stockQty.toString());
    final thresholdCtrl = TextEditingController(text: product.lowStockThreshold.toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          product.name,
          style: AppTextStyles.body(size: 15, weight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current stock', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. 24'),
            ),
            const SizedBox(height: 16),
            Text('Low-stock alert at', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: thresholdCtrl,
              keyboardType: TextInputType.number,
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. 5'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final qty = int.tryParse(qtyCtrl.text.trim());
              final threshold = int.tryParse(thresholdCtrl.text.trim());
              if (qty != null) catalog.setStock(product.id, qty);
              if (threshold != null) catalog.setLowStockThreshold(product.id, threshold);
              Navigator.of(context).pop();
            },
            child: Text('Save', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.tillGreen)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLow = product.isLowStock;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLow ? AppColors.ledgerRed.withOpacity(0.6) : AppColors.slateBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openStockDialog(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${product.stockQty} in stock',
                        style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                      ),
                      if (isLow) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.ledgerRed.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'LOW',
                            style: AppTextStyles.mono(
                              size: 10,
                              weight: FontWeight.w700,
                              color: AppColors.ledgerRed,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: AppColors.textSecondary,
            tooltip: 'Decrease stock',
            onPressed: product.stockQty <= 0 ? null : () => catalog.adjustStock(product.id, -1),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            color: AppColors.tillGreen,
            tooltip: 'Increase stock',
            onPressed: () => catalog.adjustStock(product.id, 1),
          ),
        ],
      ),
    );
  }
}
