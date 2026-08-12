import '../models/product.dart';
import '../models/product_variant.dart';

class CartItem {
  final Product product;
  // Which size was picked, for products where Product.hasVariants is
  // true. Null for every product without sizes — unchanged behavior.
  final ProductVariant? selectedVariant;
  int quantity;

  CartItem({required this.product, this.selectedVariant, this.quantity = 1});

  // Variant price wins when one was picked; otherwise the product's
  // own flat price, exactly as before variants existed.
  double get unitPrice => selectedVariant?.price ?? product.price;

  double get lineTotal => unitPrice * quantity;

  // "Coffee (Large)" vs plain "Coffee" — used anywhere a cart/receipt
  // line is rendered.
  String get displayName => selectedVariant == null
      ? product.name
      : '${product.name} (${selectedVariant!.name})';
}
