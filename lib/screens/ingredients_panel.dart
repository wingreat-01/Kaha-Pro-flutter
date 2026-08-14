import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ingredient.dart';
import '../state/ingredient_provider.dart';
import '../state/store_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';

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
class IngredientsPanel extends StatelessWidget {
  const IngredientsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreProvider>();
    final ingredients = context.watch<IngredientProvider>();
    final label = store.businessTypeLabel;
    final sorted = [...ingredients.ingredients]..sort((a, b) => a.name.compareTo(b.name));

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
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add $label',
            onPressed: () => _openEditDialog(context, label: label),
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
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ValuationSummary(ingredients: sorted),
                  for (final ingredient in sorted)
                    _IngredientRow(
                      ingredient: ingredient,
                      provider: ingredients,
                      label: label,
                    ),
                ],
              ),
      ),
    );
  }

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

  const _IngredientRow({
    required this.ingredient,
    required this.provider,
    required this.label,
  });

  void _openStockDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: _trimZeros(ingredient.stockQuantity));
    final thresholdCtrl = TextEditingController(
      text: ingredient.lowStockThreshold != null ? _trimZeros(ingredient.lowStockThreshold!) : '',
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          ingredient.name,
          style: AppTextStyles.body(size: 15, weight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current stock (${ingredient.unitDisplay})',
              style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. 500'),
            ),
            const SizedBox(height: 16),
            Text('Low-stock alert at', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: thresholdCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. 50 (optional)'),
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
              final qty = double.tryParse(qtyCtrl.text.trim());
              final threshold = double.tryParse(thresholdCtrl.text.trim());
              if (qty != null) provider.setStock(ingredient.id, qty);
              provider.updateIngredient(ingredient.id, lowStockThreshold: threshold);
              Navigator.of(context).pop();
            },
            child: Text('Save', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.tillGreen)),
          ),
        ],
      ),
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
