import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ingredient.dart';
import '../models/ingredient_stock_movement.dart';

/// Raw-materials/supplies state, backed by the ingredients table
/// (see 004_create_ingredients.sql). Entirely separate from
/// ProductProvider -- this never touches products/categories, and
/// nothing here appears in the Register grid.
///
/// Load pattern matches ProductProvider: fetch-once-on-login, not
/// realtime. Registered in main.dart's MultiProvider and loaded from
/// login_screen.dart's fetch-once-on-login Future.wait, same as
/// StoreProvider (Step 2).
class IngredientProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<Ingredient> _ingredients = [];
  bool isLoading = false;
  Object? loadError;

  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);

  List<Ingredient> get lowStockIngredients =>
      _ingredients.where((i) => i.isLowStock).toList();

  Future<void> loadFromSupabase() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final rows = await _client
          .from('ingredients')
          .select()
          .order('name');

      _ingredients = (rows as List)
          .map((row) => Ingredient.fromRow(row as Map<String, dynamic>))
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

  /// store_id isn't passed here -- same as categories' addCategory():
  /// the ingredients.store_id column defaults to current_store_id()
  /// server-side (004_create_ingredients.sql), and RLS's with-check
  /// enforces it matches on insert.
  Future<void> addIngredient({
    required String name,
    required String unit,
    String? unitLabel,
    double stockQuantity = 0,
    double? lowStockThreshold,
    double? costPerUnit,
  }) async {
    final row = await _client
        .from('ingredients')
        .insert({
          'name': name.trim(),
          'unit': unit,
          'unit_label': unitLabel,
          'stock_quantity': stockQuantity,
          'low_stock_threshold': lowStockThreshold,
          'cost_per_unit': costPerUnit,
        })
        .select()
        .single();

    _ingredients = [..._ingredients, Ingredient.fromRow(row)]
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> updateIngredient(
    String id, {
    String? name,
    String? unit,
    String? unitLabel,
    double? lowStockThreshold,
    double? costPerUnit,
  }) async {
    final index = _ingredients.indexWhere((i) => i.id == id);
    if (index < 0) return;

    final previous = _ingredients[index];
    final updated = previous.copyWith(
      name: name,
      unit: unit,
      unitLabel: unitLabel,
      lowStockThreshold: lowStockThreshold,
      costPerUnit: costPerUnit,
    );
    _ingredients[index] = updated;
    notifyListeners();

    try {
      await _client.from('ingredients').update({
        if (name != null) 'name': name.trim(),
        if (unit != null) 'unit': unit,
        'unit_label': unitLabel,
        'low_stock_threshold': lowStockThreshold,
        'cost_per_unit': costPerUnit,
      }).eq('id', id);
    } catch (e) {
      _ingredients[index] = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteIngredient(String id) async {
    final index = _ingredients.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final removed = _ingredients[index];
    _ingredients = [..._ingredients]..removeAt(index);
    notifyListeners();

    try {
      await _client.from('ingredients').delete().eq('id', id);
    } catch (e) {
      _ingredients = [..._ingredients]..insert(index, removed);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _writeStock(String id, int index, double next) async {
    final previous = _ingredients[index].stockQuantity;
    _ingredients[index] = _ingredients[index].copyWith(stockQuantity: next);
    notifyListeners();

    try {
      await _client.from('ingredients').update({'stock_quantity': next}).eq('id', id);
    } catch (e) {
      _ingredients[index] = _ingredients[index].copyWith(stockQuantity: previous);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> adjustStock(String id, double delta) async {
    final index = _ingredients.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final current = _ingredients[index].stockQuantity;
    final next = (current + delta) < 0 ? 0.0 : current + delta;
    return _writeStock(id, index, next);
  }

  Future<void> setStock(String id, double quantity) async {
    final index = _ingredients.indexWhere((i) => i.id == id);
    if (index < 0) return;
    return _writeStock(id, index, quantity < 0 ? 0 : quantity);
  }

  /// Manual owner correction WITH an audit trail -- used by the
  /// Ingredients screen's stock dialog instead of plain setStock() so
  /// every manual change has a reason attached (see
  /// 007_create_ingredient_stock_movements.sql). [delta] is signed:
  /// positive adds stock, negative deducts. Clamps at zero, same as
  /// adjustStock/setStock -- this is still a manual correction, not a
  /// sale.
  ///
  /// The stock write happens first and is what actually matters for
  /// the app to keep working; the movement-log insert is
  /// best-effort -- a failed log write shouldn't undo a real stock
  /// change the same way a failed deductStockForSale write wouldn't
  /// roll back an already-synced sale. It just means this one change
  /// won't show up in history.
  Future<void> recordManualAdjustment(
    String id, {
    required double delta,
    required String reason,
    String? note,
    String? staffId,
    String? staffName,
  }) async {
    final index = _ingredients.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final current = _ingredients[index].stockQuantity;
    final next = (current + delta) < 0 ? 0.0 : current + delta;
    await _writeStock(id, index, next);

    try {
      await _client.from('ingredient_stock_movements').insert({
        'ingredient_id': id,
        'delta': delta,
        'reason': reason,
        'note': note,
        'staff_id': staffId,
        'staff_name': staffName,
        'source': 'manual',
      });
    } catch (_) {
      // Swallowed deliberately -- see doc comment above.
    }
  }

  /// Recent movement history for one ingredient, newest first --
  /// backs the History view in the Ingredients screen. Capped at 50;
  /// this is a quick recent-activity check, not a full ledger export.
  Future<List<IngredientStockMovement>> loadMovementsFor(String ingredientId) async {
    final rows = await _client
        .from('ingredient_stock_movements')
        .select()
        .eq('ingredient_id', ingredientId)
        .order('created_at', ascending: false)
        .limit(50);

    return (rows as List)
        .map((r) => IngredientStockMovement.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Checkout-time deduction — deliberately does NOT clamp at zero the
  /// way [adjustStock]/[setStock] do. Those two are manual owner
  /// corrections (the +/- buttons and the stock dialog in the
  /// Ingredients screen), where clamping makes sense. A sale going
  /// through when the stock count was already off shouldn't be
  /// silently capped at zero — that would just make a bad count look
  /// clean instead of surfacing that a restock is overdue. No warning
  /// shown either, by design (negative-stock policy: allow, no
  /// warning) — the low-stock badge already covers "this needs
  /// attention" without interrupting a sale.
  ///
  /// [deductions] is {ingredientId: totalQuantityToSubtract}, as
  /// produced by RecipeProvider.computeDeductionsForSale. Fires one
  /// update per ingredient, same reasoning as
  /// ProductProvider.deductStockForSale's per-line-item loop — fine at
  /// today's single-till sale volume.
  Future<void> deductStockForSale(Map<String, double> deductions) async {
    for (final entry in deductions.entries) {
      final index = _ingredients.indexWhere((i) => i.id == entry.key);
      if (index < 0) continue; // ingredient was deleted after the recipe was set up
      final next = _ingredients[index].stockQuantity - entry.value;
      await _writeStock(entry.key, index, next);
    }
  }
}
