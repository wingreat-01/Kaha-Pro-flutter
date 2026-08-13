/// A raw material / supply item -- store_id-scoped, entirely separate
/// from Product. Managed from its own admin screen (ingredients_panel.dart);
/// never appears in the Register grid.
///
/// See kahapro-inventory-recipes-plan.md Step 3. This table is also the
/// picker source for the recipe editor once ProductRecipeItem exists
/// (Step 4) -- a product's recipe only *references* Ingredient rows, it
/// never creates them.
class Ingredient {
  final String id;
  final String name;
  final String unit; // pc | g | kg | ml | L | pack | sack | custom
  final String? unitLabel; // only meaningful when unit == 'custom'
  final double stockQuantity;
  final double? lowStockThreshold;
  final double? costPerUnit;

  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    this.unitLabel,
    required this.stockQuantity,
    this.lowStockThreshold,
    this.costPerUnit,
  });

  bool get isLowStock =>
      lowStockThreshold != null && stockQuantity <= lowStockThreshold!;

  /// Same idea as Product.unitDisplay -- shows the custom label when
  /// set, otherwise the plain unit code.
  String get unitDisplay =>
      unit == 'custom' && unitLabel != null && unitLabel!.isNotEmpty
          ? unitLabel!
          : unit;

  factory Ingredient.fromRow(Map<String, dynamic> row) {
    return Ingredient(
      id: row['id'] as String,
      name: row['name'] as String,
      unit: row['unit'] as String? ?? 'pc',
      unitLabel: row['unit_label'] as String?,
      stockQuantity: (row['stock_quantity'] as num).toDouble(),
      lowStockThreshold: (row['low_stock_threshold'] as num?)?.toDouble(),
      costPerUnit: (row['cost_per_unit'] as num?)?.toDouble(),
    );
  }

  Ingredient copyWith({
    String? name,
    String? unit,
    String? unitLabel,
    double? stockQuantity,
    double? lowStockThreshold,
    double? costPerUnit,
  }) {
    return Ingredient(
      id: id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      unitLabel: unitLabel ?? this.unitLabel,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      costPerUnit: costPerUnit ?? this.costPerUnit,
    );
  }
}

/// Shared unit list -- kept identical to kProductUnits in product.dart
/// so both dropdowns behave the same way (same order, same custom-label
/// pattern), even though the two models are otherwise fully separate.
const List<String> kIngredientUnits = ['pc', 'g', 'kg', 'ml', 'L', 'pack', 'sack', 'custom'];
