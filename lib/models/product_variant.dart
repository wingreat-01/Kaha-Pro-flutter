/// A selectable size/option for a product (e.g. Medium/Large/Grande for
/// a milk tea). Optional per product — a Product with an empty
/// [Product.variants] list just uses its own flat price, unchanged from
/// today's behavior.
///
/// Name and price are both freely editable from the admin Products
/// panel; there is no fixed enum of size names.
class ProductVariant {
  final String id;
  final String productId;
  final String name;
  final double price;
  final int sortOrder;

  /// Optional per-size stock count. null (the default, and what every
  /// size had before this field existed) means "this size has no count
  /// of its own" — sales of it come out of the product's shared
  /// [Product.stockQty], exactly as before. A number means this size is
  /// tracked separately: sales and manual adjustments move this count.
  final int? stockQty;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    required this.price,
    this.sortOrder = 0,
    this.stockQty,
  });

  bool get hasOwnStock => stockQty != null;

  factory ProductVariant.fromRow(Map<String, dynamic> row) {
    return ProductVariant(
      id: row['id'] as String,
      productId: row['product_id'] as String,
      name: row['name'] as String,
      price: (row['price'] as num).toDouble(),
      sortOrder: row['sort_order'] as int? ?? 0,
      stockQty: (row['stock_qty'] as num?)?.toInt(),
    );
  }

  ProductVariant copyWith({
    String? name,
    double? price,
    int? sortOrder,
    int? stockQty,
    bool clearStockQty = false, // true = back to "shares product stock"
  }) {
    return ProductVariant(
      id: id,
      productId: productId,
      name: name ?? this.name,
      price: price ?? this.price,
      sortOrder: sortOrder ?? this.sortOrder,
      stockQty: clearStockQty ? null : (stockQty ?? this.stockQty),
    );
  }
}
