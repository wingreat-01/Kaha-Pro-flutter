import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import 'product_variant_editor.dart';
import 'recipe_editor.dart';

/// Form dialog for adding a new product, or editing an existing one
/// (pass [editingProduct] to switch modes — same fields, pre-filled,
/// title/button text change, and the product-limit counter is hidden
/// since editing doesn't consume a slot). The caller (RegisterScreen /
/// wherever else this opens from) still owns talking to ProductProvider:
/// pass an onSubmit that calls addProduct for new products or
/// updateProduct for edits.
class AddProductDialog extends StatefulWidget {
  final List<String> existingCategories; // excludes 'All'
  final String? initialCategory;
  final Product? editingProduct;
  final void Function({
    required String name,
    required double price,
    required String category,
    String? emoji,
    Uint8List? imageBytes,
    bool trackStock,
    String unit,
    String? unitLabel,
    List<({String name, double price})> variants,
    List<({String ingredientId, double quantityUsed, String? variantKey})> recipeItems,
  }) onSubmit;

  /// This store's total-product cap for its plan (ProductProvider.
  /// productLimit) — null means unlimited/unknown, in which case the
  /// dialog behaves exactly as before (no counter, no lock screen).
  /// Ignored entirely when [editingProduct] is set, since editing an
  /// existing product never changes the count.
  final int? productLimit;

  /// Current total product count (ProductProvider.productCount).
  /// Ignored when [productLimit] is null or when editing.
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
    this.editingProduct,
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
  String? _existingImageUrl; // edit mode only — shown until a new photo is picked
  bool _pickingImage = false;
  bool _trackStock = false;
  String _unit = 'pc';
  final _unitLabelCtrl = TextEditingController();
  List<({String name, double price})> _draftVariants = [];
  List<({String ingredientId, double quantityUsed, String? variantKey})> _draftRecipeItems = [];

  // Deduped, order-preserving copy of widget.existingCategories.
  // DropdownButtonFormField throws an assertion if its `value` isn't
  // found in `items` exactly once — so both the value we pick AND the
  // items list itself need to come from this same deduped source.
  late final List<String> _categories;

  bool get _isEditing => widget.editingProduct != null;

  @override
  void initState() {
    super.initState();
    _categories = LinkedHashSet<String>.from(widget.existingCategories).toList();

    final editing = widget.editingProduct;
    if (editing != null) {
      _nameCtrl.text = editing.name;
      _priceCtrl.text = _formatPrice(editing.price);
      _emojiCtrl.text = editing.emoji ?? '';
      _existingImageUrl = editing.imageUrl;
      _trackStock = editing.trackStock;
      _unit = kProductUnits.contains(editing.unit) ? editing.unit : 'pc';
      _unitLabelCtrl.text = editing.unitLabel ?? '';
    }

    final initial = widget.initialCategory ?? editing?.category;
    final valid = initial != null && initial != 'All' && _categories.contains(initial);
    _selectedCategory = valid
        ? initial
        : (_categories.isNotEmpty ? _categories.first : null);
    if (_selectedCategory == null) _addingNewCategory = true;
  }

  // Trims trailing ".00" / trailing zeros so an edited price doesn't
  // show "150.00" back to the user as unnecessarily precise — but
  // keeps real cents (e.g. 49.5 -> "49.50" would be wrong too, so this
  // just uses toStringAsFixed(2) then trims trailing zeros/dot).
  String _formatPrice(double price) {
    var s = price.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _emojiCtrl.dispose();
    _newCategoryCtrl.dispose();
    _unitLabelCtrl.dispose();
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
    if (_unit == 'custom' && _unitLabelCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name for the custom unit.');
      return;
    }

    widget.onSubmit(
      name: name,
      price: price,
      category: category,
      emoji: _emojiCtrl.text,
      imageBytes: _imageBytes,
      trackStock: _trackStock,
      unit: _unit,
      unitLabel: _unit == 'custom' ? _unitLabelCtrl.text.trim() : null,
      variants: _draftVariants,
      recipeItems: _draftRecipeItems,
    );
    Navigator.of(context).pop();
  }

  bool get _atLimit =>
      !_isEditing && widget.productLimit != null && widget.currentProductCount >= widget.productLimit!;

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
                _isEditing ? 'EDIT PRODUCT' : 'ADD PRODUCT',
                style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.5),
              ),
              if (!_isEditing && widget.productLimit != null) ...[
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
                              : (_existingImageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: Image.network(_existingImageUrl!, fit: BoxFit.cover),
                                    )
                                  : Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted, size: 20))),
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
                            _existingImageUrl != null
                                ? 'Tap to replace photo'
                                : 'Overrides the emoji placeholder',
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
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _trackStock = !_trackStock),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Track stock',
                              style: AppTextStyles.body(size: 13.5, weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Auto-deduct 1 from stock on every sale (e.g. drinks/cups). '
                              'Leave off for items you restock by hand.',
                              style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _trackStock,
                        activeColor: AppColors.tillGreen,
                        onChanged: (value) => setState(() => _trackStock = value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_trackStock) ...[
                Text('Unit', style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _unit,
                  dropdownColor: AppColors.slate,
                  style: AppTextStyles.body(size: 14),
                  decoration: const InputDecoration(),
                  items: kProductUnits
                      .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u == 'custom' ? 'Custom…' : u),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _unit = value ?? 'pc'),
                ),
                if (_unit == 'custom') ...[
                  const SizedBox(height: 10),
                  _field('', _unitLabelCtrl, hint: 'e.g. roll, bundle, meter'),
                ],
                const SizedBox(height: 14),
              ],
              ProductVariantEditor(
                productId: widget.editingProduct?.id,
                initialVariants: widget.editingProduct?.variants ?? const [],
                onDraftVariantsChanged: _isEditing
                    ? null
                    // setState here (not just assignment) so the size
                    // picker inside RecipeEditor below re-renders with
                    // the current draft sizes as they're added/removed
                    // — a size added just now should be immediately
                    // selectable in "Applies to", not only after some
                    // unrelated rebuild.
                    : (drafts) => setState(() => _draftVariants = drafts),
              ),
              const SizedBox(height: 14),
              RecipeEditor(
                productId: widget.editingProduct?.id,
                onDraftRecipeItemsChanged: _isEditing
                    ? null
                    : (drafts) => _draftRecipeItems = drafts,
                // Editing: sizes already have real ids. New product:
                // sizes are still staged locally with no id yet, so
                // each gets an "idx:n" placeholder keyed to its
                // position — register_screen.dart resolves these to
                // real variant ids right after saving the sizes
                // themselves.
                sizes: _isEditing
                    ? widget.editingProduct!.variants
                        .map((v) => (key: v.id, name: v.name))
                        .toList()
                    : _draftVariants
                        .asMap()
                        .entries
                        .map((e) => (key: 'idx:${e.key}', name: e.value.name))
                        .toList(),
                priceController: _priceCtrl,
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
                  ElevatedButton(onPressed: _submit, child: Text(_isEditing ? 'Save' : 'Add')),
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
