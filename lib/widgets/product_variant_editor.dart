import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product_variant.dart';
import '../state/product_provider.dart';
import '../theme/app_theme.dart';

/// Drop-in "This product has sizes" section for the add/edit product
/// form (embedded directly in AddProductDialog).
///
/// - For a NEW product (not yet saved), pass [productId] as null —
///   rows are staged locally and reported via [onDraftVariantsChanged];
///   AddProductDialog forwards the staged list through its onSubmit,
///   and RegisterScreen attaches them via ProductProvider.addVariant
///   once the new product actually has an id.
/// - For an EXISTING product being edited, pass its real [productId]
///   and [initialVariants] — every add/rename/reprice/delete writes
///   straight through ProductProvider immediately, same as the rest
///   of the admin UI (no separate "Save" step for sizes).
class ProductVariantEditor extends StatefulWidget {
  final String? productId;
  final List<ProductVariant> initialVariants;
  final ValueChanged<List<({String name, double price})>>? onDraftVariantsChanged;

  const ProductVariantEditor({
    super.key,
    required this.productId,
    this.initialVariants = const [],
    this.onDraftVariantsChanged,
  });

  @override
  State<ProductVariantEditor> createState() => _ProductVariantEditorState();
}

class _DraftRow {
  final ProductVariant? existing; // null = not yet saved to Supabase
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  final FocusNode nameFocus = FocusNode();
  final FocusNode priceFocus = FocusNode();

  _DraftRow({this.existing, required String name, required String price})
      : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price);

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    nameFocus.dispose();
    priceFocus.dispose();
  }
}

class _ProductVariantEditorState extends State<ProductVariantEditor> {
  late bool _hasSizes;
  final List<_DraftRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _hasSizes = widget.initialVariants.isNotEmpty;
    for (final v in widget.initialVariants) {
      _rows.add(_newRow(existing: v, name: v.name, price: v.price.toStringAsFixed(2)));
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _notifyDraftChange() {
    if (widget.productId != null) return; // existing product: writes go straight to Supabase
    widget.onDraftVariantsChanged?.call(_rows
        .map((r) => (
              name: r.nameCtrl.text.trim(),
              price: double.tryParse(r.priceCtrl.text.trim()) ?? 0,
            ))
        .where((r) => r.name.isNotEmpty && r.price > 0)
        .toList());
  }

  /// True blur handling: onSubmitted/onEditingComplete only fire on a
  /// keyboard "Done"/"Next" action, not on tapping away to another
  /// widget (e.g. straight to the dialog's own Save button) — which
  /// was the actual bug (toggle appeared to reset because nothing
  /// had actually been committed yet). This listens for real focus
  /// loss on either field and commits then, in addition to the
  /// existing submit/editingComplete handlers.
  void _wireRow(_DraftRow row) {
    void maybeCommit(FocusNode node) {
      if (node.hasFocus) return; // only act when focus is LEAVING
      if (!mounted) return; // widget (dialog) already gone
      final index = _rows.indexOf(row);
      if (index == -1) return; // row was removed/disposed
      _commitRow(index);
    }

    row.nameFocus.addListener(() => maybeCommit(row.nameFocus));
    row.priceFocus.addListener(() => maybeCommit(row.priceFocus));
  }

  _DraftRow _newRow({ProductVariant? existing, required String name, required String price}) {
    final row = _DraftRow(existing: existing, name: name, price: price);
    _wireRow(row);
    return row;
  }

  void _addRow() {
    setState(() => _rows.add(_newRow(name: '', price: '')));
  }

  Future<void> _removeRow(int index) async {
    final row = _rows[index];
    if (widget.productId != null && row.existing != null) {
      setState(() => _rows.removeAt(index));
      try {
        await context.read<ProductProvider>().deleteVariant(row.existing!.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.slate,
              content: Text('Could not delete size — try again',
                  style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
            ),
          );
        }
      }
    } else {
      setState(() => _rows.removeAt(index));
      _notifyDraftChange();
    }
    row.dispose();
  }

  Future<void> _commitRow(int index) async {
    final row = _rows[index];
    final name = row.nameCtrl.text.trim();
    final price = double.tryParse(row.priceCtrl.text.trim());
    if (name.isEmpty || price == null || price <= 0) return;

    if (widget.productId == null) {
      _notifyDraftChange();
      return;
    }

    final provider = context.read<ProductProvider>();
    try {
      if (row.existing == null) {
        await provider.addVariant(widget.productId!, name: name, price: price);
        final matches = provider.products
            .firstWhere((p) => p.id == widget.productId)
            .variants
            .where((v) => v.name == name && v.price == price);
        if (matches.isNotEmpty && mounted) {
          setState(() {
            _rows[index] = _newRow(
              existing: matches.last,
              name: name,
              price: price.toStringAsFixed(2),
            );
          });
        }
      } else {
        await provider.updateVariant(row.existing!.id, name: name, price: price);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.slate,
            content: Text('Could not save size — try again',
                style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final next = !_hasSizes;
            setState(() {
              _hasSizes = next;
              if (next && _rows.isEmpty) {
                _rows.add(_newRow(name: '', price: ''));
              }
            });
            _notifyDraftChange();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('This product has sizes', style: AppTextStyles.body(size: 13.5, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'e.g. Medium, Large, Grande — each with its own price',
                        style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _hasSizes,
                  activeColor: AppColors.tillGreen,
                  onChanged: (v) {
                    setState(() {
                      _hasSizes = v;
                      if (v && _rows.isEmpty) {
                        _rows.add(_newRow(name: '', price: ''));
                      }
                    });
                    _notifyDraftChange();
                  },
                ),
              ],
            ),
          ),
        ),
        if (_hasSizes) ...[
          const SizedBox(height: 6),
          ..._rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: row.nameCtrl,
                      focusNode: row.nameFocus,
                      style: AppTextStyles.body(size: 14),
                      decoration: const InputDecoration(hintText: 'Size name (e.g. Large)'),
                      onSubmitted: (_) => _commitRow(index),
                      onEditingComplete: () => _commitRow(index),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: row.priceCtrl,
                      focusNode: row.priceFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AppTextStyles.mono(size: 14, weight: FontWeight.w600, color: AppColors.ledAmber),
                      decoration: const InputDecoration(hintText: '0.00', prefixText: '₱'),
                      onSubmitted: (_) => _commitRow(index),
                      onEditingComplete: () => _commitRow(index),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.ledgerRed, size: 20),
                    onPressed: () => _removeRow(index),
                    tooltip: 'Remove size',
                  ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add_circle_outline, color: AppColors.tillGreen, size: 18),
            label: Text('Add size', style: AppTextStyles.body(size: 12.5, weight: FontWeight.w600, color: AppColors.tillGreen)),
          ),
        ],
      ],
    );
  }
}
