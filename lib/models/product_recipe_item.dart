/// A single line in a product's recipe/BOM: "this product (optionally,
/// this specific size variant) consumes this much of this ingredient
/// per sale." See kahapro-inventory-recipes-plan.md Step 3-4.
///
/// variantId is null when the line applies regardless of size (e.g.
/// "1 lid" for any size); set when a specific variant needs a
/// different amount than the base product (e.g. "Large" using more
/// milk than "Medium").
class ProductRecipeItem {
  final String id;
  final String productId;
  final String? variantId;
  final String ingredientId;
  final double quantityUsed;

  const ProductRecipeItem({
    required this.id,
    required this.productId,
    this.variantId,
    required this.ingredientId,
    required this.quantityUsed,
  });

  factory ProductRecipeItem.fromRow(Map<String, dynamic> row) {
    return ProductRecipeItem(
      id: row['id'] as String,
      productId: row['product_id'] as String,
      variantId: row['variant_id'] as String?,
      ingredientId: row['ingredient_id'] as String,
      quantityUsed: (row['quantity_used'] as num).toDouble(),
    );
  }
}

/// A recipe line plus the ingredient's own display fields (name, unit)
/// -- what the recipe editor UI actually needs to render a row without
/// every widget having to separately look the ingredient up out of
/// IngredientProvider by id. Built client-side by joining a
/// ProductRecipeItem against IngredientProvider.ingredients; not a
/// database view.
class RecipeLine {
  final ProductRecipeItem item;
  final String ingredientName;
  final String ingredientUnitDisplay;

  const RecipeLine({
    required this.item,
    required this.ingredientName,
    required this.ingredientUnitDisplay,
  });
}
