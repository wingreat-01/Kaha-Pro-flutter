/// One physical, individually-barcoded unit of a serialized product
/// (Product.trackUnits) — e.g. one specific Ingco drill out of ten.
/// Only in-stock units are kept in memory; a sold unit is removed.
class ProductUnit {
  final String id;
  final String productId;
  final String barcode;

  const ProductUnit({required this.id, required this.productId, required this.barcode});

  factory ProductUnit.fromRow(Map<String, dynamic> row) => ProductUnit(
        id: row['id'] as String,
        productId: row['product_id'] as String,
        barcode: row['barcode'] as String,
      );
}
