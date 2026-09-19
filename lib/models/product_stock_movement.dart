/// A single manual entry in the product stock movement log (see the
/// product_stock_movements table). Read-only from the Flutter side --
/// rows are written by ProductProvider (adjustStock / setStock) and
/// never edited or deleted from here.
///
/// Sales are deliberately NOT in this log: they already live in
/// Transactions, and the Inventory Movements screen reads them from
/// there instead of keeping a second copy.
class ProductStockMovement {
  final String id;
  final String? productId; // null if the product was deleted since
  final String productName; // snapshot at the time of the change
  final String unit; // snapshot, e.g. "pc" / "mL"
  final double delta; // positive = added, negative = deducted
  final String reason;
  final String? note;
  final String? staffName;
  final DateTime createdAt;

  const ProductStockMovement({
    required this.id,
    this.productId,
    required this.productName,
    required this.unit,
    required this.delta,
    required this.reason,
    this.note,
    this.staffName,
    required this.createdAt,
  });

  factory ProductStockMovement.fromRow(Map<String, dynamic> row) {
    return ProductStockMovement(
      id: row['id'] as String,
      productId: row['product_id'] as String?,
      productName: row['product_name'] as String,
      unit: row['unit'] as String? ?? 'pc',
      delta: (row['delta'] as num).toDouble(),
      reason: row['reason'] as String,
      note: row['note'] as String?,
      staffName: row['staff_name'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}
