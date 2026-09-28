import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/product.dart';
import '../state/product_provider.dart';
import '../widgets/bounded_content.dart';

/// Settings → QR Menu — lets the owner choose which products appear
/// on the customer-facing QR ordering page, independent of stock
/// tracking. Fixes the original get_menu_for_qr behavior of filtering
/// by stock_qty, which wrongly hid untracked items like "Chicken
/// Fillet w/ rice" (no meaningful stock count) from the menu.
///
/// Reuses ProductProvider's already-loaded list (fetch-once-on-login)
/// rather than fetching separately — Settings is only reachable after
/// that load has happened.
class QrMenuPanel extends StatelessWidget {
  const QrMenuPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductProvider>().products;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('QR Menu', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      body: BoundedContent(
        child: products.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Add products first, then choose which ones show on the QR ordering menu here.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, left: 2, right: 2),
                    child: Text(
                      'Toggle which products customers can order by scanning a table QR code. Everything is on by default.',
                      style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
                    ),
                  ),
                  for (final product in products) _QrMenuRow(product: product),
                ],
              ),
      ),
    );
  }
}

class _QrMenuRow extends StatefulWidget {
  final Product product;
  const _QrMenuRow({required this.product});

  @override
  State<_QrMenuRow> createState() => _QrMenuRowState();
}

class _QrMenuRowState extends State<_QrMenuRow> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await context.read<ProductProvider>().setQrMenuVisibility(widget.product.id, value);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update this item. Please try again.', style: AppTextStyles.body(size: 13)),
            backgroundColor: AppColors.ledgerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    // Tracked-stock items that are actually sold out still get hidden
    // from the QR menu server-side (see get_menu_for_qr) even with
    // this switch on — untracked items like meals have no such gate.
    final soldOut = product.trackStock && product.stockQty <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  soldOut && product.showOnQrMenu
                      ? 'Sold out — hidden from QR menu until restocked'
                      : '₱${product.price.toStringAsFixed(2)}',
                  style: AppTextStyles.body(
                    size: 12,
                    color: soldOut && product.showOnQrMenu ? AppColors.ledgerRed : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: product.showOnQrMenu,
                  activeColor: AppColors.ledAmber,
                  onChanged: _toggle,
                ),
        ],
      ),
    );
  }
}
