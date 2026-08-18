import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ingredient.dart';
import '../models/ingredient_stock_movement.dart';
import '../state/ingredient_provider.dart';
import '../state/store_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';
import '../widgets/catalog_search_bar.dart';

/// Reasons offered on a manual stock adjustment -- see
/// _StockAdjustDialog. Deliberately a fixed short list rather than
/// free text, so History stays scannable/filterable later rather than
/// a pile of one-off phrasings.
const List<String> kStockAdjustmentReasons = [
  'Restock',
  'Spoilage / Waste',
  'Personal use',
  'Stock count correction',
  'Other',
];

/// Raw-materials/supplies admin screen — its own screen, same tier as
/// Products/Categories/Settings, not a filtered view of Products (see
/// kahapro-inventory-recipes-plan.md Step 3). Never touches the
/// Register grid or ProductProvider at all.
///
/// Named "Ingredients" in code/file name regardless of what the title
/// shows — the on-screen title and empty-state copy come from
/// StoreProvider.businessTypeLabel ("Ingredients" / "Supplies" /
/// "Raw Materials", Step 0), so a hardware store sees "Supplies" here
/// even though the class/file is still IngredientsPanel.
class IngredientsPanel extends StatefulWidget {
  // Logged-in staff member, for attributing manual stock adjustments
  // -- same info HomeShell already threads into RegisterScreen as
  // cashierName, just carried one level further via SettingsPanel.
  final String staffId;
  final String staffName;

  const IngredientsPanel({super.key, required this.staffId, required this.staffName});

  @override
  State<IngredientsPanel> createState() => _IngredientsPanelState();

  static void _openEditDialog(
    BuildContext context, {
    required String label,
    Ingredient? editing,
  }) {
    showDialog(
      context: context,
      builder: (_) => _EditIngredientDialog(label: label, editing: editing),
    );
  }
}

class _IngredientsPanelState extends State<IngredientsPanel> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreProvider>();
    final ingredients = context.watch<IngredientProvider>();
    final label = store.businessTypeLabel;
    final sorted = [...ingredients.ingredients]..sort((a, b) => a.name.compareTo(b.name));

    // Search filters the same sorted list the valuation summary and
    // rows below both read from -- valuation stays scoped to whatever
    // is currently visible, same as it would if this were a category
    // filter instead of a name search.
    final query = _searchQuery.trim().toLowerCase();
    final visible = query.isEmpty
        ? sorted
        : sorted.where((i) => i.name.toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        elevation: 0,
        title: Text(
          label,
          style: AppTextStyles.mono(size: 15, weight: FontWeight.w700, letterSpacing: 1),
        ),
        actions: [
          // suggestions come from the full unfiltered `sorted` list (not
          // `visible`) so autocomplete keeps offering every item name
          // regardless of what's currently matching the live query.
          CatalogSearchBar(
            suggestions: sorted.map((i) => i.name).toList(),
            onQueryChanged: (value) => setState(() => _searchQuery = value),
            hintText: 'Search $label…',
          ),
          IconButton(
            icon: const Icon(Icons.outbox_outlined),
            tooltip: 'Withdraw stock',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _WithdrawDialog(
                ingredients: sorted,
                provider: ingredients,
                staffId: widget.staffId,
                staffName: widget.staffName,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add $label',
            onPressed: () => IngredientsPanel._openEditDialog(context, label: label),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: BoundedContent(
        child: sorted.isEmpty
            ? Center(
                child: Text(
                  'No $label yet — tap + to add one.',
                  style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
                ),
              )
            : visible.isEmpty
                ? Center(
                    child: Text(
                      'No $label match "$_searchQuery".',
                      style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Valuation card hides while a search is active --
                      // "stock value" of a partial name-match subset
                      // reads as a misleading total, not a useful one.
                      if (query.isEmpty) _ValuationSummary(ingredients: sorted),
                      for (final ingredient in visible)
                        _IngredientRow(
                          ingredient: ingredient,
                          provider: ingredients,
                          label: label,
                          staffId: widget.staffId,
                          staffName: widget.staffName,
                        ),
                    ],
                  ),
      ),
    );
  }
}

/// Standalone withdrawal flow — search any ingredient by name, enter
/// a quantity to take out, pick a reason (free text required when
/// "Other" is picked), and it deducts immediately. This is the
/// "withdraw something not tied to a sale" path the tap-to-adjust
/// dialog on each row doesn't cover well, since that one requires
/// scrolling to find the row and re-typing the *new total* rather
/// than just "how much am I taking out". Writes through the same
/// IngredientProvider.recordManualAdjustment used by the row dialog,
/// so it lands in the same movement log.
class _WithdrawDialog extends StatefulWidget {
  final List<Ingredient> ingredients;
  final IngredientProvider provider;
  final String staffId;
  final String staffName;

  const _WithdrawDialog({
    required this.ingredients,
    required this.provider,
    required this.staffId,
    required this.staffName,
  });

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  Ingredient? _selected;
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

  void _submit() {
    if (_selected == null) {
      setState(() => _error = 'Search and select an ingredient.');
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a quantity greater than 0.');
      return;
    }
    if (qty > _selected!.stockQuantity) {
      setState(() => _error =
          'Only ${_IngredientRow._trimZeros(_selected!.stockQuantity)} ${_selected!.unitDisplay} in stock.');
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

    widget.provider.recordManualAdjustment(
      _selected!.id,
      delta: -qty,
      reason: _reason == 'Other' ? customReason : _reason!,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      staffId: widget.staffId,
      staffName: widget.staffName,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('Withdraw stock', style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Item', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Autocomplete<Ingredient>(
              displayStringForOption: (i) => i.name,
              optionsBuilder: (value) {
                if (value.text.isEmpty) return const Iterable<Ingredient>.empty();
                final query = value.text.toLowerCase();
                return widget.ingredients.where((i) => i.name.toLowerCase().contains(query));
              },
              onSelected: (i) => setState(() {
                _selected = i;
                _error = null;
              }),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  style: AppTextStyles.body(size: 14),
                  decoration: const InputDecoration(hintText: 'Type to search...'),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: AppColors.slateField,
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220, maxWidth: 300),
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
                                '${option.name} · ${_IngredientRow._trimZeros(option.stockQuantity)} ${option.unitDisplay}',
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              items: kStockAdjustmentReasons
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

/// Total ₱ value of stock currently on hand — sum of (stock_quantity ×
/// cost_per_unit) across every ingredient that has a cost set. Items
/// with no cost_per_unit are excluded from the total rather than
/// silently treated as ₱0, since that would understate the real
/// value; instead their count is called out underneath so it's clear
/// the number is a floor, not the whole picture. Hidden entirely if
/// nothing has a cost set yet — a ₱0.00 card would just be noise.
class _ValuationSummary extends StatelessWidget {
  final List<Ingredient> ingredients;
  const _ValuationSummary({required this.ingredients});

  @override
  Widget build(BuildContext context) {
    double total = 0;
    var costed = 0;
    var missing = 0;
    for (final i in ingredients) {
      if (i.costPerUnit != null) {
        total += i.costPerUnit! * i.stockQuantity;
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
            '₱${total.toStringAsFixed(2)}',
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

class _IngredientRow extends StatelessWidget {
  final Ingredient ingredient;
  final IngredientProvider provider;
  final String label;
  final String staffId;
  final String staffName;

  const _IngredientRow({
    required this.ingredient,
    required this.provider,
    required this.label,
    required this.staffId,
    required this.staffName,
  });

  void _openStockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _StockAdjustDialog(
        ingredient: ingredient,
        provider: provider,
        staffId: staffId,
        staffName: staffName,
      ),
    );
  }

  void _openHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _MovementHistoryDialog(ingredient: ingredient, provider: provider),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete ${ingredient.name}?', style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
        content: Text(
          'This removes it from your $label list. This can\'t be undone.',
          style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              provider.deleteIngredient(ingredient.id);
              Navigator.of(context).pop();
            },
            child: Text('Delete', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledgerRed)),
          ),
        ],
      ),
    );
  }

  static String _trimZeros(double value) {
    var s = value.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final isLow = ingredient.isLowStock;

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
                  Text(ingredient.name, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${_trimZeros(ingredient.stockQuantity)} ${ingredient.unitDisplay} in stock',
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
                    ingredient.costPerUnit != null
                        ? '₱${_trimZeros(ingredient.costPerUnit!)} / ${ingredient.unitDisplay}'
                        : 'Cost not set',
                    style: AppTextStyles.body(
                      size: 11.5,
                      color: ingredient.costPerUnit != null ? AppColors.textMuted : AppColors.ledgerRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 19),
            color: AppColors.textSecondary,
            tooltip: 'Stock history',
            onPressed: () => _openHistory(context),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 19),
            color: AppColors.textSecondary,
            tooltip: 'Edit',
            onPressed: () => IngredientsPanel._openEditDialog(context, label: label, editing: ingredient),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 19),
            color: AppColors.textSecondary,
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }
}

/// Stock-adjust dialog, opened by tapping an ingredient row. Splits
/// into two independent parts:
///  - Quantity: if changed from the current stock, requires a reason
///    (see kStockAdjustmentReasons) and writes through
///    IngredientProvider.recordManualAdjustment so it lands in the
///    movement log with who/why attached.
///  - Low-stock threshold: unrelated to the movement log, saved as
///    before via updateIngredient regardless of whether quantity
///    changed.
/// Stateful (unlike the old inline builder) so the reason dropdown/
/// validation error can update within the dialog.
class _StockAdjustDialog extends StatefulWidget {
  final Ingredient ingredient;
  final IngredientProvider provider;
  final String staffId;
  final String staffName;

  const _StockAdjustDialog({
    required this.ingredient,
    required this.provider,
    required this.staffId,
    required this.staffName,
  });

  @override
  State<_StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<_StockAdjustDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _thresholdCtrl;
  final _noteCtrl = TextEditingController();
  String? _reason;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: _IngredientRow._trimZeros(widget.ingredient.stockQuantity));
    _thresholdCtrl = TextEditingController(
      text: widget.ingredient.lowStockThreshold != null
          ? _IngredientRow._trimZeros(widget.ingredient.lowStockThreshold!)
          : '',
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _thresholdCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _delta {
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null) return 0;
    return qty - widget.ingredient.stockQuantity;
  }

  void _save() {
    final threshold = double.tryParse(_thresholdCtrl.text.trim());
    final delta = _delta;

    // Only require a reason when the quantity actually changed —
    // editing just the low-stock threshold shouldn't be blocked by an
    // unrelated dropdown. A tiny epsilon avoids requiring a reason
    // over float rounding noise (e.g. 500 re-typed as 500.0).
    if (delta.abs() > 0.0001 && _reason == null) {
      setState(() => _error = 'Select a reason for the stock change.');
      return;
    }

    if (delta.abs() > 0.0001) {
      widget.provider.recordManualAdjustment(
        widget.ingredient.id,
        delta: delta,
        reason: _reason!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        staffId: widget.staffId,
        staffName: widget.staffName,
      );
    }
    // Threshold always saves regardless of whether quantity changed.
    widget.provider.updateIngredient(widget.ingredient.id, lowStockThreshold: threshold);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final showReason = _delta.abs() > 0.0001;

    return AlertDialog(
      backgroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        widget.ingredient.name,
        style: AppTextStyles.body(size: 15, weight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current stock (${widget.ingredient.unitDisplay})',
              style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. 500'),
              onChanged: (_) => setState(() {}), // live-show/hide the reason picker
            ),
            if (showReason) ...[
              const SizedBox(height: 14),
              Text('Reason', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _reason,
                dropdownColor: AppColors.slate,
                style: AppTextStyles.body(size: 14),
                decoration: const InputDecoration(hintText: 'Select a reason'),
                items: kStockAdjustmentReasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (value) => setState(() {
                  _reason = value;
                  _error = null;
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                style: AppTextStyles.body(size: 13),
                decoration: const InputDecoration(hintText: 'Note (optional)'),
              ),
            ],
            const SizedBox(height: 16),
            Text('Low-stock alert at', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _thresholdCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. 50 (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _save,
          child: Text('Save', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.tillGreen)),
        ),
      ],
    );
  }
}

/// Read-only recent-activity view for one ingredient — every manual
/// adjustment (with reason/note/who) and every sale-driven deduction,
/// newest first. Opened via the history icon on each ingredient row.
class _MovementHistoryDialog extends StatelessWidget {
  final Ingredient ingredient;
  final IngredientProvider provider;

  const _MovementHistoryDialog({required this.ingredient, required this.provider});

  String _formatDelta(double delta) {
    final sign = delta > 0 ? '+' : '';
    return '$sign${_IngredientRow._trimZeros(delta)} ${ingredient.unitDisplay}';
  }

  String _formatDate(DateTime dt) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(dt.month)}/${two(dt.day)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        '${ingredient.name} — History',
        style: AppTextStyles.body(size: 15, weight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 360,
        height: 380,
        child: FutureBuilder<List<IngredientStockMovement>>(
          future: provider.loadMovementsFor(ingredient.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Could not load history — try again.',
                    style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
              );
            }
            final movements = snapshot.data ?? [];
            if (movements.isEmpty) {
              return Center(
                child: Text('No stock changes recorded yet.',
                    style: AppTextStyles.body(size: 13, color: AppColors.textMuted)),
              );
            }
            return ListView.separated(
              itemCount: movements.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.slateBorder),
              itemBuilder: (context, index) {
                final m = movements[index];
                final isAdd = m.delta > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatDelta(m.delta),
                            style: AppTextStyles.mono(
                              size: 13,
                              weight: FontWeight.w700,
                              color: isAdd ? AppColors.tillGreen : AppColors.ledgerRed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m.source == 'sale' ? 'Sale' : m.reason,
                              style: AppTextStyles.body(size: 12.5, weight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(_formatDate(m.createdAt), style: AppTextStyles.body(size: 10.5, color: AppColors.textMuted)),
                        ],
                      ),
                      if (m.note != null && m.note!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(m.note!, style: AppTextStyles.body(size: 11.5, color: AppColors.textSecondary)),
                      ],
                      if (m.staffName != null && m.staffName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(m.staffName!, style: AppTextStyles.body(size: 11, color: AppColors.textMuted)),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

/// Add/edit form — name, unit (+ custom label), starting stock, cost
/// per unit (optional, unlocks ingredient-level COGS later per the
/// plan doc's Reporting hooks section).
class _EditIngredientDialog extends StatefulWidget {
  final String label;
  final Ingredient? editing;
  const _EditIngredientDialog({required this.label, this.editing});

  @override
  State<_EditIngredientDialog> createState() => _EditIngredientDialogState();
}

class _EditIngredientDialogState extends State<_EditIngredientDialog> {
  final _nameCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _unitLabelCtrl = TextEditingController();
  String _unit = 'pc';
  String? _error;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      _nameCtrl.text = editing.name;
      _unit = kIngredientUnits.contains(editing.unit) ? editing.unit : 'pc';
      _unitLabelCtrl.text = editing.unitLabel ?? '';
      _costCtrl.text = editing.costPerUnit?.toString() ?? '';
      // Starting stock only applies on create -- editing stock/count is
      // handled by the row's tap-to-open stock dialog instead, so this
      // field doesn't show in edit mode at all (see build()).
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stockCtrl.dispose();
    _costCtrl.dispose();
    _unitLabelCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (_unit == 'custom' && _unitLabelCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name for the custom unit.');
      return;
    }
    final cost = _costCtrl.text.trim().isEmpty ? null : double.tryParse(_costCtrl.text.trim());

    final provider = context.read<IngredientProvider>();
    if (_isEditing) {
      provider.updateIngredient(
        widget.editing!.id,
        name: name,
        unit: _unit,
        unitLabel: _unit == 'custom' ? _unitLabelCtrl.text.trim() : null,
        costPerUnit: cost,
      );
    } else {
      final stock = double.tryParse(_stockCtrl.text.trim()) ?? 0;
      provider.addIngredient(
        name: name,
        unit: _unit,
        unitLabel: _unit == 'custom' ? _unitLabelCtrl.text.trim() : null,
        stockQuantity: stock,
        costPerUnit: cost,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? 'EDIT ${widget.label.toUpperCase()}' : 'ADD ${widget.label.toUpperCase()}',
                style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.5),
              ),
              const SizedBox(height: 18),
              _field('Name', _nameCtrl, hint: 'e.g. Coffee Beans'),
              const SizedBox(height: 14),
              Text('Unit', style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _unit,
                dropdownColor: AppColors.slate,
                style: AppTextStyles.body(size: 14),
                decoration: const InputDecoration(),
                items: kIngredientUnits
                    .map((u) => DropdownMenuItem(value: u, child: Text(u == 'custom' ? 'Custom…' : u)))
                    .toList(),
                onChanged: (value) => setState(() => _unit = value ?? 'pc'),
              ),
              if (_unit == 'custom') ...[
                const SizedBox(height: 10),
                _field('', _unitLabelCtrl, hint: 'e.g. roll, bundle, meter'),
              ],
              if (!_isEditing) ...[
                const SizedBox(height: 14),
                _field('Starting stock', _stockCtrl, hint: 'e.g. 1000', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ],
              const SizedBox(height: 14),
              _field('Cost per unit (optional)', _costCtrl, hint: 'e.g. 0.85', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _submit, child: Text(_isEditing ? 'Save' : 'Add')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label, style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: AppTextStyles.body(size: 14),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
