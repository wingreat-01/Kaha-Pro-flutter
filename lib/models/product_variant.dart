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

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    required this.price,
    this.sortOrder = 0,
  });

  factory ProductVariant.fromRow(Map<String, dynamic> row) {
    return ProductVariant(
      id: row['id'] as String,
      productId: row['product_id'] as String,
      name: row['name'] as String,
      price: (row['price'] as num).toDouble(),
      sortOrder: row['sort_order'] as int? ?? 0,
    );
  }

  ProductVariant copyWith({
    String? name,
    double? price,
    int? sortOrder,
  }) {
    return ProductVariant(
      id: id,
      productId: productId,
      name: name ?? this.name,
      price: price ?? this.price,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
