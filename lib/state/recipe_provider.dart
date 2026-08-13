import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/product_recipe_item.dart';
import '../models/transaction.dart';
import 'ingredient_provider.dart';

/// CRUD for a single product's recipe (product_recipe_items rows).
/// Unlike ProductProvider/IngredientProvider, this is scoped to
/// whichever one product's recipe editor is currently open, not a
/// store-wide list -- there's no "load all recipes" use case yet (that
/// would only matter for e.g. a store-wide ingredient-usage report,
/// which is Step 6, not this step). Call [loadForProduct] when the
/// edit dialog opens for an existing product; for a brand-new product
/// being created, the dialog stages rows locally instead (see
/// RecipeEditor) since there's no product_id to attach to yet.
class RecipeProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<ProductRecipeItem> _items = [];
  bool isLoading = false;
  Object? loadError;

  List<ProductRecipeItem> get items => List.unmodifiable(_items);

  Future<void> loadForProduct(String productId) async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final rows = await _client
          .from('product_recipe_items')
          .select()
          .eq('product_id', productId);

      _items = (rows as List)
          .map((row) => ProductRecipeItem.fromRow(row as Map<String, dynamic>))
          .toList();

      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      loadError = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Not optimistic -- same reasoning as ProductProvider.addVariant:
  /// the row needs a real id from Supabase before local state can key
  /// off it for later update/delete calls.
  Future<ProductRecipeItem> addItem({
    required String productId,
    String? variantId,
    required String ingredientId,
    required double quantityUsed,
  }) async {
    final row = await _client
        .from('product_recipe_items')
        .insert({
          'product_id': productId,
          'variant_id': variantId,
          'ingredient_id': ingredientId,
          'quantity_used': quantityUsed,
        })
        .select()
        .single();

    final item = ProductRecipeItem.fromRow(row);
    _items = [..._items, item];
    notifyListeners();
    return item;
  }

  /// Changing the ingredient a row points to and changing its quantity
  /// are both just column updates here -- unlike a variant's name,
  /// there's no "this is really a rename, not a new thing" ambiguity,
  /// so both fields go through the same update.
  Future<void> updateItem(
    String id, {
    String? ingredientId,
    double? quantityUsed,
  }) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final previous = _items[index];

    _items[index] = ProductRecipeItem(
      id: previous.id,
      productId: previous.productId,
      variantId: previous.variantId,
      ingredientId: ingredientId ?? previous.ingredientId,
      quantityUsed: quantityUsed ?? previous.quantityUsed,
    );
    notifyListeners();

    try {
      await _client.from('product_recipe_items').update({
        if (ingredientId != null) 'ingredient_id': ingredientId,
        if (quantityUsed != null) 'quantity_used': quantityUsed,
      }).eq('id', id);
    } catch (e) {
      _items[index] = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteItem(String id) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final removed = _items[index];
    _items = [..._items]..removeAt(index);
    notifyListeners();

    try {
      await _client.from('product_recipe_items').delete().eq('id', id);
    } catch (e) {
      _items = [..._items]..insert(index, removed);
      notifyListeners();
      rethrow;
    }
  }

  /// Call when the edit dialog closes so a stale product's rows don't
  /// leak into the next time it opens for a different product.
  void clear() {
    _items = [];
    notifyListeners();
  }

  /// Checkout-time lookup: for each cart line, finds that product's
  /// recipe rows and returns the total ingredient deductions across
  /// the whole sale, aggregated as {ingredientId: totalQuantity}.
  Future<Map<String, double>> computeDeductionsForSale(List<CartItem> soldItems) {
    return _computeDeductions(soldItems.map((i) => (
          productId: i.product.id,
          variantId: i.selectedVariant?.id,
          quantity: i.quantity,
        )));
  }

  /// Same lookup, but from a queued offline sale's saved
  /// TransactionLineItem snapshots instead of live CartItems — mirrors
  /// ProductProvider.deductStockForLineItems' reasoning exactly: by
  /// the time a queued sale finally syncs, there's no CartItem/Product
  /// object left, only the flat record TransactionProvider persisted,
  /// so this works off variantId/quantity already snapshotted on the
  /// line item instead.
  Future<Map<String, double>> computeDeductionsForLineItems(List<TransactionLineItem> items) {
    return _computeDeductions(items.map((i) => (
          productId: i.productId,
          variantId: i.variantId,
          quantity: i.quantity,
        )));
  }

  /// Convenience wrapper for the offline-sync call sites
  /// (login_screen.dart / home_shell.dart) — computes and applies in
  /// one call, same shape as ProductProvider.deductStockForLineItems
  /// so both can be called side by side. [ingredients] is passed in
  /// rather than read via context here since this provider has no
  /// BuildContext of its own to read from.
  Future<void> deductForLineItems(
    List<TransactionLineItem> items,
    IngredientProvider ingredients,
  ) async {
    final deductions = await computeDeductionsForLineItems(items);
    if (deductions.isNotEmpty) {
      await ingredients.deductStockForSale(deductions);
    }
  }

  /// Shared aggregation core for both public compute methods above.
  /// Doesn't touch [_items]/[isLoading] at all -- those belong to
  /// whichever single product's recipe editor might currently be open
  /// in a dialog, and this runs independently of that.
  ///
  /// Variant resolution: if a line sold a specific variant AND that
  /// variant has its own recipe rows (variant_id matches), those rows
  /// REPLACE the base (variant_id null) rows for this line rather than
  /// adding to them -- e.g. "Large" having its own milk amount means
  /// the base milk row doesn't also apply. Not yet exercised in
  /// practice since the current recipe editor UI (Step 4) never
  /// creates variant-specific rows, but the schema supports it and
  /// this resolves it correctly if/when that UI exists.
  ///
  /// A product with no recipe rows at all contributes nothing here --
  /// exactly as before, its own Product.stockQty is what
  /// ProductProvider's deduction methods already handle separately.
  Future<Map<String, double>> _computeDeductions(
    Iterable<({String productId, String? variantId, int quantity})> lines,
  ) async {
    final linesList = lines.toList();
    final productIds = linesList
        .map((l) => l.productId)
        .where((id) => id.isNotEmpty) // product deleted before this synced
        .toSet()
        .toList();
    if (productIds.isEmpty) return {};

    // One query per distinct product rather than a single IN(...)
    // query -- keeps this independent of exactly which postgrest-dart
    // filter method/version is in use, and at typical cart sizes (a
    // handful of distinct products) the extra round trips are the
    // same non-issue as the existing addVariant-per-size loop
    // elsewhere in the app.
    final rowsByProduct = <String, List<ProductRecipeItem>>{};
    for (final productId in productIds) {
      final rows = await _client
          .from('product_recipe_items')
          .select()
          .eq('product_id', productId);
      rowsByProduct[productId] = (rows as List)
          .map((row) => ProductRecipeItem.fromRow(row as Map<String, dynamic>))
          .toList();
    }

    final deductions = <String, double>{};
    for (final line in linesList) {
      // A product deleted before this synced (see
      // ProductProvider.deductStockForLineItems' matching guard) has
      // an empty productId here too -- rowsByProduct just won't have
      // an entry for it, same effect as skipping it explicitly.
      final recipeRows = rowsByProduct[line.productId] ?? const [];
      if (recipeRows.isEmpty) continue;

      final variantRows = line.variantId == null
          ? const <ProductRecipeItem>[]
          : recipeRows.where((r) => r.variantId == line.variantId).toList();
      final applicable = variantRows.isNotEmpty
          ? variantRows
          : recipeRows.where((r) => r.variantId == null).toList();

      for (final row in applicable) {
        final amount = row.quantityUsed * line.quantity;
        deductions[row.ingredientId] = (deductions[row.ingredientId] ?? 0) + amount;
      }
    }

    return deductions;
  }
}
