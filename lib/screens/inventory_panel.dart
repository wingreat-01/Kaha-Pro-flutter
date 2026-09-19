import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/currency_provider.dart';
import '../state/product_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';
import '../widgets/catalog_search_bar.dart';

/// Real inventory list/add/edit panel — reached from Settings → Products.
/// Shows every product with its current stock, flags anything at or
/// below its own low-stock threshold, and lets you bump stock up/down
/// or restock/recount via a small dialog.
///
/// Stock lives on Product itself (stockQty, lowStockThreshold) rather
/// than a separate parallel list, so it can't drift out of sync with
/// the catalog the way category names once did between RegisterScreen
/// and ProductProvider.
class InventoryPanel extends StatefulWidget {
  // Logged-in staff member, so manual stock changes in the Inventory
  // Movements log show who made them. Optional -- left blank if not
  // passed.
  final String? staffName;

  const InventoryPanel({super.key, this.staffName});

  @override
  State<InventoryPanel> createState() => _InventoryPanelState();
}

class _InventoryPanelState extends State<InventoryPanel> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ProductProvider>();

    // Inventory only lists products with Track stock switched on --
    // made-to-order items (meals, etc.) have no stock to count, so they
    // stay out of this screen entirely.
    final tracked = catalog.products.where((p) => p.trackStock).toList();

    // Search filters the product list before it's grouped by category,
    // same approach as IngredientsPanel -- suggestions below come from
    // the full unfiltered catalog so autocomplete keeps offering every
    // product name regardless of what the live query currently matches.
    final query = _searchQuery.trim().toLowerCase();
    final matching = query.isEmpty
        ? tracked
        : tracked.where((p) => p.name.toLowerCase().contains(query)).toList();

    final byCategory = <String, List<Product>>{};
    for (final product in matching) {
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
        actions: [
          CatalogSearchBar(
            suggestions: tracked.map((p) => p.name).toList(),
            onQueryChanged: (value) => setState(() => _searchQuery = value),
            hintText: 'Search Inventory…',
          ),
          IconButton(
            icon: const Icon(Icons.outbox_outlined),
            tooltip: 'Withdraw stock',
            onPressed: tracked.isEmpty
                ? null
                : () => showDialog(
                      context: context,
                      builder: (_) => _WithdrawDialog(
                        products: [...tracked]..sort((a, b) => a.name.compareTo(b.name)),
                        provider: catalog,
                        staffName: widget.staffName,
                      ),
                    ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: BoundedContent(
        child: tracked.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'No tracked products yet.\nTurn on "Track stock" when adding or editing a product to list it here.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
                  ),
                ),
              )
            : matching.isEmpty
                ? Center(
                    child: Text(
                      'No products match "$_searchQuery".',
                      style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _ValuationSummary(products: tracked),
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
                          _InventoryRow(product: product, catalog: catalog, staffName: widget.staffName),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
      ),
    );
  }
}

String _trimZeros(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Total value of stock currently on hand -- sum of (stock quantity x
/// cost per unit) across every tracked product that has a cost set.
/// Same behavior as the Supplies & Materials card: products with no
/// cost are left out of the total rather than counted as zero (that
/// would understate the real value) and their count is shown underneath
/// so it's clear the number is a floor. Hidden entirely until at least
/// one product has a cost -- a zero-value card would just be noise.
class _ValuationSummary extends StatelessWidget {
  final List<Product> products;
  const _ValuationSummary({required this.products});

  @override
  Widget build(BuildContext context) {
    double total = 0;
    var costed = 0;
    var missing = 0;
    for (final p in products) {
      if (p.costPerUnit != null) {
        total += p.costPerUnit! * p.stockQty;
        costed++;
      } else {
        missing++;
      }
    }
    if (costed == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STOCK VALUE',
            style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            context.money(total),
            style: AppTextStyles.mono(size: 22, weight: FontWeight.w700, color: AppColors.ledAmber),
          ),
          if (missing > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$missing item${missing == 1 ? '' : 's'} missing cost per unit — not included',
              style: AppTextStyles.body(size: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  final Product product;
  final ProductProvider catalog;
  final String? staffName;

  const _InventoryRow({required this.product, required this.catalog, this.staffName});

  void _openStockDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: product.stockQty.toString());
    final thresholdCtrl = TextEditingController(text: product.lowStockThreshold.toString());
    final costCtrl = TextEditingController(
      text: product.costPerUnit == null ? '' : _trimZeros(product.costPerUnit!),
    );
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          product.name,
          style: AppTextStyles.body(size: 15, weight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
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
            const SizedBox(height: 16),
            Text(
              'Cost per ${product.unitDisplay} (optional)',
              style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: costCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. 12.50'),
            ),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final qty = int.tryParse(qtyCtrl.text.trim());
              final threshold = int.tryParse(thresholdCtrl.text.trim());
              // Empty clears the cost ("not set"); a valid number sets
              // it; anything unparseable leaves it as it was.
              final costText = costCtrl.text.trim();
              final cost = costText.isEmpty ? null : double.tryParse(costText);
              final costChanged = (costText.isEmpty || cost != null) && cost != product.costPerUnit;
              if (qty != null) catalog.setStock(product.id, qty, staffName: staffName);
              if (threshold != null) catalog.setLowStockThreshold(product.id, threshold);
              Navigator.of(context).pop();
              if (costChanged) {
                try {
                  await catalog.setCostPerUnit(product.id, cost);
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Could not save the cost — check your connection and try again.')),
                  );
                }
              }
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
                  const SizedBox(height: 2),
                  Text(
                    product.costPerUnit != null
                        ? '${context.moneyPrefix}${_trimZeros(product.costPerUnit!)} / ${product.unitDisplay}'
                        : 'Cost not set',
                    style: AppTextStyles.body(
                      size: 11.5,
                      color: product.costPerUnit != null ? AppColors.textMuted : AppColors.ledgerRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: AppColors.textSecondary,
            tooltip: 'Decrease stock',
            onPressed: product.stockQty <= 0 ? null : () => catalog.adjustStock(product.id, -1, staffName: staffName),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            color: AppColors.tillGreen,
            tooltip: 'Increase stock',
            onPressed: () => catalog.adjustStock(product.id, 1, staffName: staffName),
          ),
        ],
      ),
    );
  }
}

/// Reasons offered on a withdrawal. Same idea as the Supplies &
/// Materials list (a fixed short list so history stays scannable),
/// minus "Restock" -- that's stock coming in, not going out.
const List<String> _kWithdrawReasons = [
  'Spoilage / Waste',
  'Personal use',
  'Stock count correction',
  'Other',
];

/// Standalone withdrawal flow, same as Supplies & Materials -- search
/// a product by name, enter how many to take out, pick a reason
/// (free text required for "Other"), and it deducts immediately.
/// Writes through ProductProvider.adjustStock, so it lands in the
/// Inventory Movements log as a Withdrawal with the reason, note and
/// staff name.
class _WithdrawDialog extends StatefulWidget {
  final List<Product> products;
  final ProductProvider provider;
  final String? staffName;

  const _WithdrawDialog({
    required this.products,
    required this.provider,
    this.staffName,
  });

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  Product? _selected;
  final _qtyCtrl = TextEditingController();
  final _otherReasonCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _reason;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _otherReasonCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final product = _selected;
    if (product == null) {
      setState(() => _error = 'Search and select a product.');
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a whole number greater than 0.');
      return;
    }
    if (qty > product.stockQty) {
      setState(() => _error = 'Only ${product.stockQty} ${product.unitDisplay} in stock.');
      return;
    }
    if (_reason == null) {
      setState(() => _error = 'Select a reason.');
      return;
    }
    final customReason = _otherReasonCtrl.text.trim();
    if (_reason == 'Other' && customReason.isEmpty) {
      setState(() => _error = 'Enter a reason.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final reason = _reason == 'Other' ? customReason : _reason!;
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    Navigator.of(context).pop();

    try {
      await widget.provider.adjustStock(
        product.id,
        -qty,
        reason: reason,
        note: note,
        staffName: widget.staffName,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not withdraw stock — check your connection and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same sizing as the Supplies & Materials withdraw dialog: nearly
    // full width on phones, capped and centered on wide screens.
    const maxDialogWidth = 560.0;
    const minSideMargin = 12.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalInset = screenWidth > maxDialogWidth + (minSideMargin * 2)
        ? (screenWidth - maxDialogWidth) / 2
        : minSideMargin;
    final contentWidth = screenWidth - (horizontalInset * 2) - 48;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24),
      backgroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('Withdraw stock', style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Item', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Autocomplete<Product>(
                displayStringForOption: (p) => p.name,
                optionsBuilder: (value) {
                  if (value.text.isEmpty) return const Iterable<Product>.empty();
                  final query = value.text.toLowerCase();
                  return widget.products.where((p) => p.name.toLowerCase().contains(query));
                },
                onSelected: (p) => setState(() {
                  _selected = p;
                  _error = null;
                }),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    style: AppTextStyles.body(size: 14),
                    decoration: const InputDecoration(hintText: 'Type to search...'),
                    // Typing again after picking an item clears the pick,
                    // so the withdrawal can't go to a product that no
                    // longer matches what the field says.
                    onChanged: (_) {
                      if (_selected != null) setState(() => _selected = null);
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: AppColors.slateField,
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 220, maxWidth: contentWidth),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(option),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Text(
                                  '${option.name} · ${option.stockQty} ${option.unitDisplay}',
                                  style: AppTextStyles.body(size: 13),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                _selected != null
                    ? 'Qty to withdraw (${_selected!.unitDisplay})'
                    : 'Qty to withdraw',
                style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(size: 14),
                decoration: const InputDecoration(hintText: 'e.g. 20'),
              ),
              const SizedBox(height: 14),
              Text('Reason', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _reason,
                dropdownColor: AppColors.slate,
                style: AppTextStyles.body(size: 14),
                decoration: const InputDecoration(hintText: 'Select a reason'),
                items: _kWithdrawReasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (value) => setState(() {
                  _reason = value;
                  _error = null;
                }),
              ),
              if (_reason == 'Other') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _otherReasonCtrl,
                  style: AppTextStyles.body(size: 13),
                  decoration: const InputDecoration(hintText: 'Enter reason'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                style: AppTextStyles.body(size: 13),
                decoration: const InputDecoration(hintText: 'Note (optional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Withdraw', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledgerRed)),
        ),
      ],
    );
  }
}
