import 'package:flutter/foundation.dart';
import '../data/mock_products.dart';
import '../models/product.dart';

/// Product catalog state. Seeded from the mock data for now —
/// swap the seed for a real inventory/backend fetch in Phase 3.
class ProductProvider extends ChangeNotifier {
  final List<Product> _products = List.of(mockProducts);

  List<Product> get products => List.unmodifiable(_products);

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
  }) {
    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    _products.add(Product(
      id: id,
      name: name,
      price: price,
      category: category,
      emoji: (emoji == null || emoji.trim().isEmpty) ? null : emoji.trim(),
    ));
    notifyListeners();
  }

  void removeProduct(String id) {
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }
}
