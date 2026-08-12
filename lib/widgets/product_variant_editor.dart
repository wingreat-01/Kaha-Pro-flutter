import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product_variant.dart';
import '../state/product_provider.dart';

/// Design tokens — mirrors KahaPro's existing theme constants.
/// If the app already has a central AppColors/AppTheme file, swap
/// these out for that instead of duplicating hex values here.
class _VariantEditorColors {
  static const charcoal = Color(0xFF1E2126);
  static const slate = Color(0xFF2A2E35);
  static const ledAmber = Color(0xFFFFB020);
  static const tillGreen = Color(0xFF3FA796);
  static const ledgerRed = Color(0xFFE4572E);
  static const paperCream = Color(0xFFF6F1E4);
}

/// Drop-in "This product has sizes" section for the add/edit product
/// form. Embed it wherever the form already has fields like stock
/// qty / low-stock threshold / track-stock toggle.
///
/// - For a NEW product (not yet saved), pass [productId] as null —
///   the toggle still works but rows are staged locally in
///   [onDraftVariantsChanged] and only actually written to Supabase
///   once the parent form calls addVariant() per row after the
///   product itself is created (see usage note below).
/// - For an EXISTING product being edited, pass its real
///   [productId] and [initialVariants] — every add/rename/reprice/
///   delete here writes straight through ProductProvider immediately,
///   same as the rest of the admin UI (no separate "Save" step needed
///   for sizes specifically).
class ProductVariantEditor extends StatefulWidget {
  final String? productId;
  final List<ProductVariant> initialVariants;

  /// Only used in the "new product, no id yet" case — lets the parent
  /// form grab the staged (name, price) pairs at submit time and call
  /// ProductProvider.addVariant() for each once the product row
  /// exists. Ignored once [productId] is non-null.
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

  _DraftRow({this.existing, required String name, required String price})
      : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price);

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
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
      _rows.add(_DraftRow(
        existing: v,
        name: v.name,
        price: v.price.toStringAsFixed(2),
      ));
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
    if (widget.productId != null) return; // existing product: no draft mode
    widget.onDraftVariantsChanged?.call(_rows
        .map((r) => (
              name: r.nameCtrl.text.trim(),
              price: double.tryParse(r.priceCtrl.text.trim()) ?? 0,
            ))
        .where((r) => r.name.isNotEmpty)
        .toList());
  }

  Future<void> _addRow() async {
    setState(() {
      _rows.add(_DraftRow(name: '', price: ''));
    });
  }

  Future<void> _removeRow(int index) async {
    final row = _rows[index];
    if (widget.productId != null && row.existing != null) {
      // Existing, saved size — delete it server-side. Optimistic
      // removal from the visible list; ProductProvider handles its
      // own rollback if the delete fails, we just surface the error.
      setState(() => _rows.removeAt(index));
      try {
        await context.read<ProductProvider>().deleteVariant(row.existing!.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete size: $e')),
          );
        }
      }
    } else {
      // Draft row, never saved — just drop it locally.
      setState(() => _rows.removeAt(index));
      _notifyDraftChange();
    }
    row.dispose();
  }

  Future<void> _commitRow(int index) async {
    final row = _rows[index];
    final name = row.nameCtrl.text.trim();
    final price = double.tryParse(row.priceCtrl.text.trim());
    if (name.isEmpty || price == null) return;

    if (widget.productId == null) {
      _notifyDraftChange();
      return;
    }

    final provider = context.read<ProductProvider>();
    try {
      if (row.existing == null) {
        await provider.addVariant(widget.productId!, name: name, price: price);
        // Pick up the real id/sortOrder that came back so future
        // edits to this row target the right row.
        final saved = provider.products
            .firstWhere((p) => p.id == widget.productId)
            .variants
            .where((v) => v.name == name && v.price == price)
            .toList();
        if (saved.isNotEmpty && mounted) {
          setState(() {
            _rows[index] = _DraftRow(
              existing: saved.last,
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
          SnackBar(content: Text('Could not save size: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeColor: _VariantEditorColors.ledAmber,
          title: const Text(
            'This product has sizes',
            style: TextStyle(color: _VariantEditorColors.paperCream, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'e.g. Medium, Large, Grande — each with its own price',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          value: _hasSizes,
          onChanged: (v) {
            setState(() {
              _hasSizes = v;
              if (v && _rows.isEmpty) {
                _rows.add(_DraftRow(name: '', price: ''));
              }
            });
            _notifyDraftChange();
          },
        ),
        if (_hasSizes) ...[
          const SizedBox(height: 8),
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
                      style: const TextStyle(color: _VariantEditorColors.paperCream),
                      decoration: InputDecoration(
                        hintText: 'Size name (e.g. Large)',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: _VariantEditorColors.slate,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _commitRow(index),
                      onEditingComplete: () => _commitRow(index),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: row.priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        color: _VariantEditorColors.ledAmber,
                        fontFamily: 'IBMPlexMono',
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        prefixText: '₱',
                        prefixStyle: const TextStyle(color: _VariantEditorColors.ledAmber),
                        hintText: '0.00',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: _VariantEditorColors.slate,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _commitRow(index),
                      onEditingComplete: () => _commitRow(index),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: _VariantEditorColors.ledgerRed),
                    onPressed: () => _removeRow(index),
                    tooltip: 'Remove size',
                  ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add_circle_outline, color: _VariantEditorColors.tillGreen),
            label: const Text(
              'Add size',
              style: TextStyle(color: _VariantEditorColors.tillGreen, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}
