import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ingredient.dart';
import '../models/product_recipe_item.dart';
import '../state/ingredient_provider.dart';
import '../state/recipe_provider.dart';
import '../state/store_provider.dart';
import '../theme/app_theme.dart';

/// Drop-in "This product uses [ingredients/supplies/raw materials]"
/// section for AddProductDialog, mirroring ProductVariantEditor's
/// pattern exactly:
///
/// - For a NEW product (not yet saved), pass [productId] as null —
///   rows are staged locally and reported via
///   [onDraftRecipeItemsChanged]; AddProductDialog forwards the staged
///   list through its onSubmit, and RegisterScreen attaches them via
///   RecipeProvider.addItem once the new product actually has an id.
/// - For an EXISTING product being edited, pass its real [productId] —
///   every add/change-ingredient/change-quantity/delete writes
///   straight through RecipeProvider immediately.
///
/// Only ever references ingredients via IngredientProvider's existing
/// list (the picker) — this widget never creates new ingredients; the
/// Ingredients screen (Step 3) stays the one place that happens (see
/// plan doc's Admin UI section).
///
/// Simplification vs. the full plan doc: every row applies to the base
/// product regardless of size (variant_id always null here). Per-size
/// recipe overrides (e.g. "Large" using more milk than "Medium") are
/// a real feature the schema already supports, just not exposed in
/// this first pass of the UI — flagging this as a known gap rather
/// than a decision, in case per-size recipes turn out to matter soon.
class RecipeEditor extends StatefulWidget {
  final String? productId;
  final ValueChanged<List<({String ingredientId, double quantityUsed})>>? onDraftRecipeItemsChanged;

  /// Optional — when passed, a live "Cost: ₱X · Margin Y%" line is
  /// shown under the recipe rows, recomputed as ingredients/quantities
  /// change and as this controller's text changes. Owned by the
  /// caller (AddProductDialog's own price field controller); this
  /// widget only reads it, never disposes it.
  final TextEditingController? priceController;

  const RecipeEditor({
    super.key,
    required this.productId,
    this.onDraftRecipeItemsChanged,
    this.priceController,
  });

  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _CostResult {
  final double total;
  final bool incomplete;
  const _CostResult({required this.total, required this.incomplete});
}

class _DraftRow {
  final ProductRecipeItem? existing; // null = not yet saved to Supabase
  String? ingredientId;
  final TextEditingController qtyCtrl;
  final FocusNode qtyFocus = FocusNode();

  _DraftRow({this.existing, this.ingredientId, required String qty})
      : qtyCtrl = TextEditingController(text: qty);

  void dispose() {
    qtyCtrl.dispose();
    qtyFocus.dispose();
  }
}

class _RecipeEditorState extends State<RecipeEditor> {
  bool _hasRecipe = false;
  final List<_DraftRow> _rows = [];
  bool _loadedExisting = false;

  // Target margin for the suggested-price row under the cost summary.
  // Margin here means (price - cost) / price, matching the same
  // definition used for the margin% shown next to cost above — not a
  // markup-on-cost percentage, which would be a different number.
  static const List<int> _marginOptions = [20, 30, 40, 50, 60];
  int _targetMarginPct = 40;

  bool get _isEditing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    widget.priceController?.addListener(_onPriceChanged);
    if (_isEditing) {
      // Existing product: fetch this product's current recipe once the
      // frame is up, rather than in initState directly, since
      // context.read needs the widget tree mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final provider = context.read<RecipeProvider>();
        await provider.loadForProduct(widget.productId!);
        if (!mounted) return;
        setState(() {
          _hasRecipe = provider.items.isNotEmpty;
          for (final item in provider.items) {
            _rows.add(_newRow(existing: item, ingredientId: item.ingredientId, qty: _formatQty(item.quantityUsed)));
          }
          _loadedExisting = true;
        });
      });
    }
  }

  void _onPriceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.priceController?.removeListener(_onPriceChanged);
    for (final row in _rows) {
      row.dispose();
    }
    if (_isEditing) {
      // Clear so a stale product's rows don't leak into the next time
      // this editor opens for a different product.
      context.read<RecipeProvider>().clear();
    }
    super.dispose();
  }

  String _formatQty(double qty) {
    var s = qty.toStringAsFixed(3);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  void _notifyDraftChange() {
    if (_isEditing) return; // existing product: writes go straight to Supabase
    widget.onDraftRecipeItemsChanged?.call(_rows
        .where((r) => r.ingredientId != null)
        .map((r) => (
              ingredientId: r.ingredientId!,
              quantityUsed: double.tryParse(r.qtyCtrl.text.trim()) ?? 0,
            ))
        .where((r) => r.quantityUsed > 0)
        .toList());
  }

  void _wireRow(_DraftRow row) {
    void maybeCommit(FocusNode node) {
      if (node.hasFocus) return;
      if (!mounted) return;
      final index = _rows.indexOf(row);
      if (index == -1) return;
      _commitRow(index);
    }

    row.qtyFocus.addListener(() => maybeCommit(row.qtyFocus));
    row.qtyCtrl.addListener(() {
      if (mounted) setState(() {}); // live cost/margin recompute while typing
    });
  }

  _DraftRow _newRow({ProductRecipeItem? existing, String? ingredientId, required String qty}) {
    final row = _DraftRow(existing: existing, ingredientId: ingredientId, qty: qty);
    _wireRow(row);
    return row;
  }

  void _addRow() {
    setState(() => _rows.add(_newRow(qty: '')));
  }

  Future<void> _removeRow(int index) async {
    final row = _rows[index];
    if (_isEditing && row.existing != null) {
      setState(() => _rows.removeAt(index));
      try {
        await context.read<RecipeProvider>().deleteItem(row.existing!.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.slate,
              content: Text('Could not remove ingredient — try again',
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

  Future<void> _onIngredientChanged(int index, String? ingredientId) async {
    setState(() => _rows[index].ingredientId = ingredientId);
    await _commitRow(index);
  }

  Future<void> _commitRow(int index) async {
    final row = _rows[index];
    final ingredientId = row.ingredientId;
    final qty = double.tryParse(row.qtyCtrl.text.trim());
    if (ingredientId == null || qty == null || qty <= 0) return;

    if (!_isEditing) {
      _notifyDraftChange();
      return;
    }

    final provider = context.read<RecipeProvider>();
    try {
      if (row.existing == null) {
        final saved = await provider.addItem(
          productId: widget.productId!,
          ingredientId: ingredientId,
          quantityUsed: qty,
        );
        if (mounted) {
          setState(() {
            _rows[index] = _newRow(existing: saved, ingredientId: ingredientId, qty: _formatQty(qty));
          });
        }
      } else {
        await provider.updateItem(row.existing!.id, ingredientId: ingredientId, quantityUsed: qty);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.slate,
            content: Text('Could not save — try again',
                style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
          ),
        );
      }
    }
  }

  /// Sums (quantity_used × cost_per_unit) across every row that has
  /// both an ingredient picked and a valid quantity. `incomplete` is
  /// true if any such row's ingredient has no cost_per_unit set — in
  /// that case `total` is still the sum of what IS known, but the
  /// summary shows it as incomplete rather than a number that would
  /// silently understate true cost. Returns null when there's nothing
  /// to show yet (no valid rows).
  _CostResult? _computeCost(Map<String, Ingredient> byId) {
    double total = 0;
    var incomplete = false;
    var any = false;
    for (final row in _rows) {
      final id = row.ingredientId;
      if (id == null) continue;
      final ingredient = byId[id];
      if (ingredient == null) continue;
      final qty = double.tryParse(row.qtyCtrl.text.trim());
      if (qty == null || qty <= 0) continue;
      any = true;
      if (ingredient.costPerUnit == null) {
        incomplete = true;
      } else {
        total += ingredient.costPerUnit! * qty;
      }
    }
    if (!any) return null;
    return _CostResult(total: total, incomplete: incomplete);
  }

  Widget _buildCostSummary(Map<String, Ingredient> byId) {
    final result = _computeCost(byId);
    if (result == null) return const SizedBox.shrink();

    if (result.incomplete) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          "Cost: incomplete — set a cost per unit on all materials used to see margin",
          style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
        ),
      );
    }

    final cost = result.total;
    final priceText = widget.priceController?.text.trim();
    final price = priceText != null ? double.tryParse(priceText) : null;

    final Widget costLine;
    if (price == null || price <= 0) {
      costLine = Text(
        'Cost: ₱${cost.toStringAsFixed(2)}',
        style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary),
      );
    } else {
      final profit = price - cost;
      final marginPct = (profit / price) * 100;
      final color = marginPct < 0
          ? AppColors.ledgerRed
          : marginPct < 20
              ? AppColors.ledAmber
              : AppColors.tillGreen;
      costLine = Text(
        'Cost: ₱${cost.toStringAsFixed(2)} · Margin ${marginPct.toStringAsFixed(0)}% (₱${profit.toStringAsFixed(2)})',
        style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: color),
      );
    }

    final suggestion = _buildSuggestedPriceRow(cost);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          costLine,
          if (suggestion != null) ...[
            const SizedBox(height: 6),
            suggestion,
          ],
        ],
      ),
    );
  }

  /// "Suggested price for 40% margin: ₱25.00 [Use]" — only shown when
  /// there's somewhere to write the price to (priceController passed
  /// in) and a real cost to base it on. Margin dropdown lets the
  /// owner try a few targets without leaving the dialog; tapping "Use"
  /// fills the actual price field, which (via the priceController
  /// listener in initState) immediately updates the cost/margin line
  /// above to match.
  Widget? _buildSuggestedPriceRow(double cost) {
    if (widget.priceController == null || cost <= 0) return null;
    final suggested = cost / (1 - _targetMarginPct / 100);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text('Suggested price for', style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
        DropdownButton<int>(
          value: _targetMarginPct,
          dropdownColor: AppColors.slate,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: AppTextStyles.body(size: 11.5, color: AppColors.textSecondary),
          items: _marginOptions
              .map((m) => DropdownMenuItem(value: m, child: Text('$m%')))
              .toList(),
          onChanged: (value) => setState(() => _targetMarginPct = value ?? _targetMarginPct),
        ),
        Text('margin: ₱${suggested.toStringAsFixed(2)}', style: AppTextStyles.mono(size: 11.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => widget.priceController!.text = suggested.toStringAsFixed(2),
          child: Text('Use', style: AppTextStyles.body(size: 11.5, weight: FontWeight.w700, color: AppColors.tillGreen)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = context.watch<StoreProvider>().businessTypeLabel;
    final ingredients = context.watch<IngredientProvider>().ingredients;
    final byId = <String, Ingredient>{for (final i in ingredients) i.id: i};

    // Still fetching this product's existing recipe -- show nothing
    // rather than a flash of an empty toggle before rows land.
    if (_isEditing && !_loadedExisting) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final next = !_hasRecipe;
            setState(() {
              _hasRecipe = next;
              if (next && _rows.isEmpty) {
                _rows.add(_newRow(qty: ''));
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
                      Text('This product uses ${label.toLowerCase()}',
                          style: AppTextStyles.body(size: 13.5, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Auto-deduct these from stock on every sale, instead of the product\'s own stock count.',
                        style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _hasRecipe,
                  activeColor: AppColors.tillGreen,
                  onChanged: (v) {
                    setState(() {
                      _hasRecipe = v;
                      if (v && _rows.isEmpty) {
                        _rows.add(_newRow(qty: ''));
                      }
                    });
                    _notifyDraftChange();
                  },
                ),
              ],
            ),
          ),
        ),
        if (_hasRecipe) ...[
          const SizedBox(height: 6),
          if (ingredients.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No $label yet — add some from Settings first.',
                style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
              ),
            )
          else
            ..._rows.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              final selected = row.ingredientId != null ? byId[row.ingredientId] : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: row.ingredientId != null && byId.containsKey(row.ingredientId) ? row.ingredientId : null,
                        dropdownColor: AppColors.slate,
                        style: AppTextStyles.body(size: 13),
                        decoration: const InputDecoration(hintText: 'Pick one'),
                        isExpanded: true,
                        items: ingredients
                            .map((i) => DropdownMenuItem(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (value) => _onIngredientChanged(index, value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.qtyCtrl,
                        focusNode: row.qtyFocus,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: AppTextStyles.mono(size: 14, weight: FontWeight.w600, color: AppColors.ledAmber),
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: selected?.unitDisplay,
                        ),
                        onSubmitted: (_) => _commitRow(index),
                        onEditingComplete: () => _commitRow(index),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.ledgerRed, size: 20),
                      onPressed: () => _removeRow(index),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            }),
          if (ingredients.isNotEmpty)
            TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add_circle_outline, color: AppColors.tillGreen, size: 18),
              label: Text('Add ${label.toLowerCase()} used', style: AppTextStyles.body(size: 12.5, weight: FontWeight.w600, color: AppColors.tillGreen)),
            ),
          _buildCostSummary(byId),
        ],
      ],
    );
  }
}
