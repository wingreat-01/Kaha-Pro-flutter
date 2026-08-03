import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../data/mock_products.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

/// Product catalog state. Seeded from the mock data for now —
/// swap the seed for a real inventory/backend fetch in Phase 3.
class ProductProvider extends ChangeNotifier {
  final List<Product> _products = List.of(mockProducts);

  List<Product> get products => List.unmodifiable(_products);

  /// Products at or below their own low-stock threshold — feeds the
  /// LOW badge in InventoryPanel and can back a dashboard warning later.
  List<Product> get lowStockProducts => _products.where((p) => p.isLowStock).toList();

  /// 'All' plus every distinct category currently in the catalog,
  /// so newly-added categories show up in the nav automatically.
  List<String> get categories {
    final distinct = _products.map((p) => p.category).toSet().toList()..sort();
    return ['All', ...distinct];
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
