/// A single entry in an ingredient's stock movement log (see
/// 007_create_ingredient_stock_movements.sql). Read-only from the
/// Flutter side -- rows are written by IngredientProvider
/// (recordManualAdjustment) and by checkout-time sale deduction, never
/// edited or deleted from here.
class IngredientStockMovement {
  final String id;
  final String ingredientId;
  final double delta; // positive = added, negative = deducted
  final String reason;
  final String? note;
  final String? staffName;
  final String source; // 'manual' | 'sale'
  final DateTime createdAt;

  const IngredientStockMovement({
    required this.id,
    required this.ingredientId,
    required this.delta,
    required this.reason,
    this.note,
    this.staffName,
    required this.source,
    required this.createdAt,
  });

  factory IngredientStockMovement.fromRow(Map<String, dynamic> row) {
    return IngredientStockMovement(
      id: row['id'] as String,
      ingredientId: row['ingredient_id'] as String,
      delta: (row['delta'] as num).toDouble(),
      reason: row['reason'] as String,
      note: row['note'] as String?,
      staffName: row['staff_name'] as String?,
      source: row['source'] as String? ?? 'manual',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}
