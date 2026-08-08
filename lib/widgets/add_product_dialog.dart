import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
    Uint8List? imageBytes,
  }) onSubmit;

  /// This store's total-product cap for its plan (ProductProvider.
  /// productLimit) — null means unlimited/unknown, in which case the
  /// dialog behaves exactly as before (no counter, no lock screen).
  final int? productLimit;

  /// Current total product count (ProductProvider.productCount).
  /// Ignored when [productLimit] is null.
  final int currentProductCount;

  /// Called when the user taps "Upgrade" on the limit-reached screen.
  /// Optional so this dialog doesn't need to know how upgrade
  /// navigation works yet — wire it up once that screen exists.
  final VoidCallback? onUpgradeTap;

  const AddProductDialog({
    super.key,
    required this.existingCategories,
    required this.onSubmit,
    this.initialCategory,
    this.productLimit,
    this.currentProductCount = 0,
    this.onUpgradeTap,
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
  Uint8List? _imageBytes;
  bool _pickingImage = false;

  // Deduped, order-preserving copy of widget.existingCategories.
  // DropdownButtonFormField throws an assertion if its `value` isn't
  // found in `items` exactly once — so both the value we pick AND the
  // items list itself need to come from this same deduped source.
  late final List<String> _categories;

  @override
  void initState() {
    super.initState();
    _categories = LinkedHashSet<String>.from(widget.existingCategories).toList();

    final initial = widget.initialCategory;
    final valid = initial != null && initial != 'All' && _categories.contains(initial);
    _selectedCategory = valid
        ? initial
        : (_categories.isNotEmpty ? _categories.first : null);
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

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
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
      imageBytes: _imageBytes,
    );
    Navigator.of(context).pop();
  }

  bool get _atLimit =>
      widget.productLimit != null && widget.currentProductCount >= widget.productLimit!;

  @override
  Widget build(BuildContext context) {
    if (_atLimit) return _buildLimitReachedDialog(context);

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
              if (widget.productLimit != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${widget.currentProductCount}/${widget.productLimit} products used',
                  style: AppTextStyles.mono(size: 10.5, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.5),
                ),
              ],
              const SizedBox(height: 18),
              _field('Name', _nameCtrl, hint: 'e.g. Bottled Water'),
              const SizedBox(height: 14),
              _field('Price', _priceCtrl, hint: '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 14),
              _field('Emoji (optional)', _emojiCtrl, hint: '🛒'),
              const SizedBox(height: 14),
              Text('Photo (optional)', style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.charcoal,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: _pickingImage
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ledAmber),
                              ),
                            )
                          : (_imageBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                                )
                              : Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _imageBytes != null
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _imageBytes = null),
                              child: Text('Remove photo', style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
                            ),
                          )
                        : Text(
                            'Overrides the emoji placeholder',
                            style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Category', style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              if (!_addingNewCategory && _categories.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory != null && _categories.contains(_selectedCategory)
                            ? _selectedCategory
                            : null,
                        dropdownColor: AppColors.slate,
                        style: AppTextStyles.body(size: 14),
                        decoration: const InputDecoration(),
                        items: _categories
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
                    if (_categories.isNotEmpty)
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

  Widget _buildLimitReachedDialog(BuildContext context) {
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
              'PRODUCT LIMIT REACHED',
              style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.ledgerRed, letterSpacing: 1.5),
            ),
            const SizedBox(height: 14),
            Text(
              "You've used all ${widget.productLimit} products on your current plan. "
              'Upgrade to add more.',
              style: AppTextStyles.body(size: 13.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onUpgradeTap?.call();
                  },
                  child: const Text('Upgrade'),
                ),
              ],
            ),
          ],
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
