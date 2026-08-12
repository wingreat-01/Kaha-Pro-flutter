import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/product_provider.dart';
import '../theme/app_theme.dart';

/// Small dialog for moving a single product into a different category.
/// The tap target for this is the product's own tile/row wherever it's
/// listed (e.g. Settings → Categories → Uncategorized detail view) —
/// this dialog itself doesn't fetch or navigate, it just does the move.
class ReassignCategoryDialog extends StatefulWidget {
  final Product product;

  /// Categories the product can be moved into. Exclude 'All' and
  /// 'Uncategorized' before passing this in — 'All' isn't a real
  /// category, and Uncategorized is a fallback the product is already
  /// in, not a destination.
  final List<String> availableCategories;

  const ReassignCategoryDialog({
    super.key,
    required this.product,
    required this.availableCategories,
  });

  /// Convenience opener. Returns true if the move happened, false if
  /// the user cancelled or it failed.
  static Future<bool> show(
    BuildContext context, {
    required Product product,
    required List<String> availableCategories,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ReassignCategoryDialog(
        product: product,
        availableCategories: availableCategories,
      ),
    );
    return result ?? false;
  }

  @override
  State<ReassignCategoryDialog> createState() => _ReassignCategoryDialogState();
}

class _ReassignCategoryDialogState extends State<ReassignCategoryDialog> {
  String? _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.availableCategories.isNotEmpty ? widget.availableCategories.first : null;
  }

  Future<void> _save(ProductProvider catalog) async {
    final target = _selected;
    if (target == null) {
      setState(() => _error = 'Pick a category.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await catalog.updateProductCategory(widget.product.id, target);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't move product — try again";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<ProductProvider>();

    return Dialog(
      backgroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MOVE TO CATEGORY',
              style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              widget.product.name,
              style: AppTextStyles.body(size: 13.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            if (widget.availableCategories.isEmpty)
              Text(
                'No categories to move this into yet — add one in Categories first.',
                style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
              )
            else
              DropdownButtonFormField<String>(
                value: _selected,
                dropdownColor: AppColors.slate,
                style: AppTextStyles.body(size: 14),
                decoration: const InputDecoration(),
                items: widget.availableCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) => setState(() => _selected = value),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_saving || widget.availableCategories.isEmpty) ? null : () => _save(catalog),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.charcoal),
                        )
                      : const Text('Move'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
