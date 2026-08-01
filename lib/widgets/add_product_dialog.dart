import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Form dialog for adding a new product. Returns the entered values
/// via onSubmit; the caller (RegisterScreen) owns talking to ProductProvider.
class AddProductDialog extends StatefulWidget {
  final List<String> existingCategories; // excludes 'All'
  final String? initialCategory;
  final void Function({
    required String name,
    required double price,
    required String category,
    String? emoji,
  }) onSubmit;

  const AddProductDialog({
    super.key,
    required this.existingCategories,
    required this.onSubmit,
    this.initialCategory,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();

  String? _selectedCategory;
  bool _addingNewCategory = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final valid = widget.initialCategory != null && widget.initialCategory != 'All';
    _selectedCategory = valid
        ? widget.initialCategory
        : (widget.existingCategories.isNotEmpty ? widget.existingCategories.first : null);
    if (_selectedCategory == null) _addingNewCategory = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _emojiCtrl.dispose();
    _newCategoryCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final priceText = _priceCtrl.text.trim();
    final price = double.tryParse(priceText);
    final category = _addingNewCategory ? _newCategoryCtrl.text.trim() : (_selectedCategory ?? '');

    if (name.isEmpty) {
      setState(() => _error = 'Product name is required.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    if (category.isEmpty) {
      setState(() => _error = 'Pick or enter a category.');
      return;
    }

    widget.onSubmit(
      name: name,
      price: price,
      category: category,
      emoji: _emojiCtrl.text,
    );
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
                'ADD PRODUCT',
                style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.5),
              ),
              const SizedBox(height: 18),
              _field('Name', _nameCtrl, hint: 'e.g. Bottled Water'),
              const SizedBox(height: 14),
              _field('Price', _priceCtrl, hint: '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 14),
              _field('Emoji (optional)', _emojiCtrl, hint: '🛒'),
              const SizedBox(height: 14),
              Text('Category', style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              if (!_addingNewCategory && widget.existingCategories.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        dropdownColor: AppColors.slate,
                        style: AppTextStyles.body(size: 14),
                        decoration: const InputDecoration(),
                        items: widget.existingCategories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (value) => setState(() => _selectedCategory = value),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _addingNewCategory = true),
                      child: Text('New', style: AppTextStyles.body(size: 12, color: AppColors.ledAmber)),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: _field('', _newCategoryCtrl, hint: 'New category name')),
                    if (widget.existingCategories.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _addingNewCategory = false),
                        child: Text('Pick existing', style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
                      ),
                  ],
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _submit, child: const Text('Add')),
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
