import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../state/product_provider.dart';

/// Categories admin panel — reached via Settings → Categories. Categories
/// are now a real stored list (see ProductProvider), so this can add an
/// empty category, rename one (which bulk-updates every product in it),
/// or delete one (which moves its products into the `Uncategorized`
/// fallback rather than leaving them dangling).
class CategoriesPanel extends StatelessWidget {
  const CategoriesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final categories = provider.categoryNames;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('Categories', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ledAmber,
        foregroundColor: AppColors.charcoal,
        onPressed: () => _showCategoryForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: categories.length,
        itemBuilder: (context, i) => _CategoryRow(name: categories[i]),
      ),
    );
  }

  static void _showCategoryForm(BuildContext context, {String? existing}) {
    showDialog(
      context: context,
      builder: (_) => _CategoryFormDialog(existing: existing),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String name;
  const _CategoryRow({required this.name});

  bool get _isProtected => name == ProductProvider.uncategorized;

  @override
  Widget build(BuildContext context) {
    final count = context.watch<ProductProvider>().productCountForCategory(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isProtected ? null : () => CategoriesPanel._showCategoryForm(context, existing: name),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.slateField,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slateBorder, width: 1),
                ),
                child: Icon(
                  _isProtected ? Icons.inbox_outlined : Icons.category_outlined,
                  size: 18,
                  color: AppColors.ledAmber,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _isProtected
                          ? '$count product${count == 1 ? '' : 's'} • fallback bucket, can\'t be edited or deleted'
                          : '$count product${count == 1 ? '' : 's'}',
                      style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!_isProtected)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: AppColors.ledgerRed),
                  onPressed: () => _confirmDelete(context, name, count),
                )
              else
                Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String name, int count) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text('Delete category?', style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
        content: Text(
          count > 0
              ? 'Delete "$name"? $count product${count == 1 ? '' : 's'} in it will move to "${ProductProvider.uncategorized}".'
              : 'Delete "$name"? It has no products in it.',
          style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: AppTextStyles.body(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              context.read<ProductProvider>().deleteCategory(name);
              Navigator.of(dialogContext).pop();
            },
            child: Text('Delete', style: AppTextStyles.body(color: AppColors.ledgerRed, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Add/rename form. `existing` null means "add new"; non-null means
/// rename that category (never called for the protected bucket — the
/// row disables its own tap for that case).
class _CategoryFormDialog extends StatefulWidget {
  final String? existing;
  const _CategoryFormDialog({this.existing});

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _nameController;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final provider = context.read<ProductProvider>();

    if (name.isEmpty) {
      setState(() => _error = 'Category name is required.');
      return;
    }
    if (name.toLowerCase() == 'all') {
      setState(() => _error = '"All" is reserved.');
      return;
    }
    final isDuplicate = provider.categoryNames.any(
      (c) => c.toLowerCase() == name.toLowerCase() && c != widget.existing,
    );
    if (isDuplicate) {
      setState(() => _error = 'A category with that name already exists.');
      return;
    }

    if (_isEditing) {
      provider.renameCategory(widget.existing!, name);
    } else {
      provider.addCategory(name);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text(
        _isEditing ? 'Rename category' : 'Add category',
        style: AppTextStyles.body(size: 16, weight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            style: AppTextStyles.body(size: 14),
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            _isEditing ? 'Save' : 'Add',
            style: AppTextStyles.body(color: AppColors.ledAmber, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
