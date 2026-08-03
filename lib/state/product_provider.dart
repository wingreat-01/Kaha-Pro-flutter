import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../data/mock_products.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

/// Product catalog state. Seeded from the mock data for now —
/// swap the seed for a real inventory/backend fetch in Phase 3.
class ProductProvider extends ChangeNotifier {
  /// Fallback bucket products land in when their category is deleted.
  /// Always present, can't be renamed or deleted (see categories_panel.dart).
  static const String uncategorized = 'Uncategorized';

  final List<Product> _products = List.of(mockProducts);

  /// Real, independently-stored category list (order = insertion order).
  /// Categories can now exist with zero products in them — this is what
  /// makes that possible, as opposed to the old approach of deriving the
  /// list purely from whatever's on the products.
  final List<String> _categoryNames = [];

  ProductProvider() {
    // Seed from whatever's on the mock products, preserving first-seen
    // order, then guarantee the fallback bucket always exists.
    final seen = <String>{};
    for (final p in _products) {
      if (seen.add(p.category)) _categoryNames.add(p.category);
    }
    if (!_categoryNames.contains(uncategorized)) {
      _categoryNames.add(uncategorized);
    }
  }

  List<Product> get products => List.unmodifiable(_products);

  /// Products at or below their own low-stock threshold — feeds the
  /// LOW badge in InventoryPanel and can back a dashboard warning later.
  List<Product> get lowStockProducts => _products.where((p) => p.isLowStock).toList();

  /// The real stored category list, excluding the virtual 'All' filter.
  /// Used by CategoriesPanel and by AddProductDialog's category picker.
  List<String> get categoryNames => List.unmodifiable(_categoryNames);

  /// 'All' plus every stored category, for nav/tabs — same shape callers
  /// already expect from before categories became a real stored list.
  List<String> get categories => ['All', ..._categoryNames];

  int productCountForCategory(String name) {
    return _products.where((p) => p.category == name).length;
  }

  /// Adds a category if it isn't already present (case-sensitive match,
  /// same as everywhere else categories are compared). Silently no-ops
  /// on a duplicate — callers doing user-facing validation (e.g. a
  /// case-insensitive duplicate check) should check before calling this.
  void addCategory(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _categoryNames.contains(trimmed)) return;
    _categoryNames.add(trimmed);
    notifyListeners();
  }

  /// Renames a category and updates every product currently in it to
  /// match. No-ops if [oldName] isn't a real stored category, or if
  /// [oldName] is the protected `uncategorized` bucket.
  void renameCategory(String oldName, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (oldName == uncategorized) return;
    final index = _categoryNames.indexOf(oldName);
    if (index == -1) return;

    _categoryNames[index] = trimmed;
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].category == oldName) {
        _products[i] = _products[i].copyWith(category: trimmed);
      }
    }
    notifyListeners();
  }

  /// Deletes a category. Any products still in it move to the
  /// `uncategorized` bucket rather than being left dangling. No-ops on
  /// the protected `uncategorized` bucket itself — that one can't be
  /// removed since it's the fallback everything else reassigns to.
  void deleteCategory(String name) {
    if (name == uncategorized) return;
    if (!_categoryNames.remove(name)) return;

    if (!_categoryNames.contains(uncategorized)) {
      _categoryNames.add(uncategorized);
    }
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].category == name) {
        _products[i] = _products[i].copyWith(category: uncategorized);
      }
    }
    notifyListeners();
  }

  void addProduct({
    required String name,
    required double price,
    required String category,
    String? emoji,
    Uint8List? imageBytes,
    int stockQty = 0,
    int lowStockThreshold = 5,
  }) {
    // Keep the AddProductDialog "type a new category" flow working —
    // if this is a category we haven't seen, register it for real
    // instead of leaving it as a string that only lives on this product.
    addCategory(category);

    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    _products.add(Product(
      id: id,
      name: name,
      price: price,
      category: category,
      emoji: (emoji == null || emoji.trim().isEmpty) ? null : emoji.trim(),
      imageBytes: imageBytes,
      stockQty: stockQty,
      lowStockThreshold: lowStockThreshold,
    ));
    notifyListeners();
  }

  void removeProduct(String id) {
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// Replaces a product's photo with the given bytes (from the image
  /// picker). Pass null to clear a custom photo and fall back to the
  /// emoji placeholder again.
  void updateProductImage(String id, Uint8List? imageBytes) {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _products[index] = _products[index].copyWith(imageBytes: imageBytes);
    notifyListeners();
  }

  /// Adjusts stock by [delta] (positive to restock, negative to deduct —
  /// e.g. on checkout). Clamps at 0, never goes negative.
  void adjustStock(String id, int delta) {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final current = _products[index].stockQty;
    final next = (current + delta) < 0 ? 0 : current + delta;
    _products[index] = _products[index].copyWith(stockQty: next);
    notifyListeners();
  }

  /// Sets stock to an exact value — used for manual counts/corrections
  /// rather than incremental restocks.
  void setStock(String id, int quantity) {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _products[index] = _products[index].copyWith(stockQty: quantity < 0 ? 0 : quantity);
    notifyListeners();
  }

  /// Deducts stock for a completed sale — one call per checkout, right
  /// after the sale is logged and before the cart is cleared, so the
  /// quantities sold still match what was actually charged.
  void deductStockForSale(List<CartItem> soldItems) {
    for (final item in soldItems) {
      adjustStock(item.product.id, -item.quantity);
    }
  }

  void setLowStockThreshold(String id, int threshold) {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _products[index] = _products[index].copyWith(lowStockThreshold: threshold < 0 ? 0 : threshold);
    notifyListeners();
  }
}
