import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/transaction.dart';

/// Product catalog state, backed by Supabase (categories/products
/// tables). Phase D of the Supabase migration — replaces the mock-data
/// seed with a real fetch, scoped to the caller's store via RLS.
///
/// Load pattern: fetch-once-on-login, not realtime. Call
/// [loadFromSupabase] right after a successful sign-in and before
/// showing HomeShell; nothing auto-refreshes after that until the next
/// login (matches today's single-till, single-device usage).
/// Thrown by [ProductProvider.addProduct] when the store is at its
/// plan's product cap — either caught locally before any network call
/// (the common case), or surfaced from the server-side
/// `enforce_product_limit` Postgres trigger (errcode P0001) if the
/// local check and the server ever disagree (e.g. plan changed on
/// another device, or this session's plan hasn't loaded yet). The
/// trigger is the real gate; this class exists so UI code can catch a
/// specific type instead of pattern-matching on PostgrestException.
class ProductLimitExceededException implements Exception {
  final String message;
  const ProductLimitExceededException(this.message);

  @override
  String toString() => message;
}

class ProductProvider extends ChangeNotifier {
  static const String uncategorized = 'Uncategorized';
  static const String _imageBucket = 'product-images';

  /// Per-plan total-product caps (all categories combined) — mirrors
  /// the `product_limit()` function backing the Postgres trigger. This
  /// copy is UI-only (for the live counter/lock in AddProductDialog);
  /// the trigger is what actually enforces it. null = unlimited.
  static const Map<String, int?> _productLimits = {
    'free': 5,
    'basic': 30,
    'pro': null,
  };

  final SupabaseClient _client = Supabase.instance.client;

  List<Product> _products = [];
  final List<String> _categoryNames = [];

  /// Null until [loadFromSupabase] fetches it, or if that fetch fails.
  /// Treated as "unknown" rather than defaulting to 'free', so a fetch
  /// hiccup never falsely locks a paying Basic/Pro store out of adding
  /// products in the UI — the trigger still enforces the real cap
  /// regardless of whether this loaded.
  String? _plan;
  String? get plan => _plan;

  /// category name -> category id, needed since the DB stores
  /// products.category_id (a FK), while the rest of the app works with
  /// plain category name strings on Product.
  final Map<String, String> _categoryIds = {};

  bool isLoading = false;
  Object? loadError;

  List<Product> get products => List.unmodifiable(_products);

  List<Product> get lowStockProducts =>
      _products.where((p) => p.isLowStock).toList();

  List<String> get categoryNames => List.unmodifiable(_categoryNames);

  List<String> get categories => ['All', ..._categoryNames];

  int productCountForCategory(String name) {
    return _products.where((p) => p.category == name).length;
  }

  /// This store's total-product cap for its current plan. Null means
  /// either Pro (genuinely unlimited) or the plan hasn't loaded yet —
  /// callers that need to tell those apart should check [plan] too.
  int? get productLimit => _plan == null ? null : _productLimits[_plan];

  int get productCount => _products.length;

  bool get isAtProductLimit {
    final limit = productLimit;
    return limit != null && productCount >= limit;
  }

  /// Null means unlimited (or plan not loaded). Never negative.
  int? get remainingProductSlots {
    final limit = productLimit;
    if (limit == null) return null;
    final remaining = limit - productCount;
    return remaining < 0 ? 0 : remaining;
  }

  /// Uploads a product photo to Supabase Storage and returns its public
  /// URL. Path is scoped by the signed-in owner's auth uid (this app's
  /// actual tenant boundary — a shared owner session per store, per
  /// PIN-gated staff auth) rather than a separate store_id, so the
  /// Storage RLS policy can check auth.uid() directly against the
  /// object's folder without needing a join back to the store table.
  /// upsert: true so re-uploading a photo for the same product just
  /// overwrites the old file instead of accumulating orphaned ones.
  Future<String> _uploadProductImage(String productId, Uint8List bytes) async {
    final uid = _client.auth.currentUser!.id;
    final path = '$uid/$productId.jpg';
    await _client.storage.from(_imageBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return _client.storage.from(_imageBucket).getPublicUrl(path);
  }

  /// Fetches this store's categories and products. Call once, right
  /// after login. Categories load first since products need the
  /// id->name map to reconstruct their category field.
  Future<void> loadFromSupabase() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      // Drives the product-count cap shown in the UI (productLimit /
      // isAtProductLimit above). Isolated in its own try/catch — a
      // failure here shouldn't take down the whole catalog load, and
      // leaving _plan null just means the UI won't show a cap this
      // session while the enforce_product_limit trigger still governs
      // actual inserts.
      try {
        final storeRow = await _client.from('stores').select('plan').single();
        _plan = storeRow['plan'] as String?;
      } catch (e) {
        debugPrint('loadFromSupabase: could not fetch store plan: $e');
      }

      final categoryRows = await _client
          .from('categories')
          .select('id, name, is_protected')
          .order('created_at', ascending: true);

      _categoryNames.clear();
      _categoryIds.clear();
      for (final row in categoryRows as List) {
        final name = row['name'] as String;
        _categoryNames.add(name);
        _categoryIds[name] = row['id'] as String;
      }

      final productRows = await _client
          .from('products')
          .select('*, categories(name), product_variants(*)')
          .order('created_at', ascending: true);

      _products = (productRows as List)
          .map((row) => _productFromRow(row as Map<String, dynamic>))
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

  Product _productFromRow(Map<String, dynamic> row) {
    final categoryName =
        (row['categories'] as Map<String, dynamic>?)?['name'] as String? ??
            uncategorized;
    final variantRows = (row['product_variants'] as List?) ?? const [];
    final variants = variantRows
        .map((v) => ProductVariant.fromRow(v as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Product(
      id: row['id'] as String,
      name: row['name'] as String,
      price: (row['price'] as num).toDouble(),
      category: categoryName,
      emoji: row['emoji'] as String?,
      imageUrl: row['image_url'] as String?,
      stockQty: row['stock_qty'] as int,
      lowStockThreshold: row['low_stock_threshold'] as int,
      trackStock: row['track_stock'] as bool? ?? false,
      unit: row['unit'] as String? ?? 'pc',
      unitLabel: row['unit_label'] as String?,
      variants: variants,
    );
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _categoryNames.contains(trimmed)) return;

    // Optimistic local add so the UI feels instant.
    _categoryNames.add(trimmed);
    notifyListeners();

    try {
      final row = await _client
          .from('categories')
          .insert({'name': trimmed})
          .select('id')
          .single();
      _categoryIds[trimmed] = row['id'] as String;
    } catch (e) {
      // Roll back on failure (e.g. a race with another device adding
      // the same name — unique(store_id, name) would reject it).
      _categoryNames.remove(trimmed);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> renameCategory(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (oldName == uncategorized) return; // DB trigger would reject this too
    final index = _categoryNames.indexOf(oldName);
    if (index == -1) return;
    final categoryId = _categoryIds[oldName];
    if (categoryId == null) return;

    final previous = _categoryNames[index];
    _categoryNames[index] = trimmed;
    _categoryIds.remove(oldName);
    _categoryIds[trimmed] = categoryId;
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].category == oldName) {
        _products[i] = _products[i].copyWith(category: trimmed);
      }
    }
    notifyListeners();

    try {
      await _client.from('categories').update({'name': trimmed}).eq('id', categoryId);
    } catch (e) {
      // Roll back the rename locally.
      _categoryNames[index] = previous;
      _categoryIds.remove(trimmed);
      _categoryIds[previous] = categoryId;
      for (var i = 0; i < _products.length; i++) {
        if (_products[i].category == trimmed) {
          _products[i] = _products[i].copyWith(category: previous);
        }
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteCategory(String name) async {
    if (name == uncategorized) return;
    final categoryId = _categoryIds[name];
    if (categoryId == null) return;
    if (!_categoryNames.remove(name)) return;

    if (!_categoryNames.contains(uncategorized)) {
      _categoryNames.add(uncategorized);
    }
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].category == name) {
        _products[i] = _products[i].copyWith(category: uncategorized);
      }
    }
    notifyListeners();

    try {
      // Single RPC call — reassigns products to Uncategorized and
      // deletes the category row atomically server-side.
      await _client.rpc('delete_category', params: {'target_category_id': categoryId});
      _categoryIds.remove(name);
    } catch (e) {
      // Not attempting a full local rollback here since the products
      // reassignment above is harmless either way (Uncategorized is a
      // valid fallback); re-fetch to get back to a known-good state.
      await loadFromSupabase();
      rethrow;
    }
  }

  /// Returns the new product's id — needed by callers that stage
  /// variants (sizes) in the add-product dialog before the product
  /// exists yet, so they can attach them right after creation via
  /// [addVariant].
  Future<String> addProduct({
    required String name,
    required double price,
    required String category,
    String? emoji,
    Uint8List? imageBytes,
    int stockQty = 0,
    int lowStockThreshold = 5,
    bool trackStock = false,
    String unit = 'pc',
    String? unitLabel,
  }) async {
    // Local pre-check — catches the common case instantly, no network
    // round trip, and avoids creating a new category (addCategory
    // below) for a product that's about to be rejected anyway. Not
    // the real gate: the enforce_product_limit trigger is (see the
    // catch block further down), since this check can be stale if the
    // plan changed on another device or hasn't loaded this session.
    if (isAtProductLimit) {
      throw ProductLimitExceededException(
        'Product limit reached for your plan ($productLimit max). '
        'Upgrade to add more products.',
      );
    }

    if (!_categoryNames.contains(category)) {
      await addCategory(category);
    }
    final categoryId = _categoryIds[category];
    if (categoryId == null) {
      throw StateError('Could not resolve category id for "$category"');
    }

    try {
      final row = await _client
          .from('products')
          .insert({
            'name': name,
            'price': price,
            'category_id': categoryId,
            'emoji': (emoji == null || emoji.trim().isEmpty) ? null : emoji.trim(),
            'stock_qty': stockQty,
            'low_stock_threshold': lowStockThreshold,
            'track_stock': trackStock,
            'unit': unit,
            'unit_label': (unitLabel == null || unitLabel.trim().isEmpty) ? null : unitLabel.trim(),
          })
          .select()
          .single();

      final newId = row['id'] as String;
      String? imageUrl;
      if (imageBytes != null) {
        try {
          imageUrl = await _uploadProductImage(newId, imageBytes);
          final updated = await _client
              .from('products')
              .update({'image_url': imageUrl})
              .eq('id', newId)
              .select();
          if ((updated as List).isEmpty) {
            // RLS silently blocked the update — no exception, but the
            // row wasn't touched. Surface this like any other failure
            // rather than pretending it worked.
            throw StateError('image_url update matched no rows (RLS?) for product $newId');
          }
        } catch (e) {
          // Product row is already created — don't fail the whole add
          // over a photo upload hiccup. It just comes in without a
          // photo; the camera badge in edit mode lets it be added again.
          debugPrint('addProduct: image upload/save failed for $newId: $e');
          imageUrl = null;
        }
      }

      _products.add(Product(
        id: newId,
        name: name,
        price: price,
        category: category,
        emoji: (emoji == null || emoji.trim().isEmpty) ? null : emoji.trim(),
        imageUrl: imageUrl,
        stockQty: stockQty,
        lowStockThreshold: lowStockThreshold,
        trackStock: trackStock,
        unit: unit,
        unitLabel: (unitLabel == null || unitLabel.trim().isEmpty) ? null : unitLabel.trim(),
      ));
      notifyListeners();
      return newId;
    } catch (e) {
      // The real gate: enforce_product_limit trigger rejects the
      // insert server-side (errcode P0001) if the local pre-check
      // above was stale — e.g. another device added the last slot in
      // the gap between the check and this request landing.
      if (e is PostgrestException && e.code == 'P0001') {
        throw ProductLimitExceededException(e.message);
      }
      rethrow;
    }
  }

  /// Full edit — name, price, category, emoji. The general-purpose
  /// counterpart to [updateProductCategory] (which this now delegates
  /// to when only the category actually changes, so there's one write
  /// path instead of two slightly different ones).
  Future<void> updateProduct(
    String id, {
    required String name,
    required double price,
    required String category,
    String? emoji,
    bool? trackStock,
    String? unit,
    String? unitLabel,
  }) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final previous = _products[index];

    if (!_categoryNames.contains(category)) {
      await addCategory(category);
    }
    final categoryId = _categoryIds[category];
    if (categoryId == null) return;

    final trimmedEmoji = (emoji == null || emoji.trim().isEmpty) ? null : emoji.trim();
    final resolvedTrackStock = trackStock ?? previous.trackStock;
    final resolvedUnit = unit ?? previous.unit;
    final resolvedUnitLabel = unit == null ? previous.unitLabel : unitLabel;

    _products[index] = Product(
      id: previous.id,
      name: name,
      price: price,
      category: category,
      emoji: trimmedEmoji,
      imageUrl: previous.imageUrl,
      stockQty: previous.stockQty,
      lowStockThreshold: previous.lowStockThreshold,
      trackStock: resolvedTrackStock,
      unit: resolvedUnit,
      unitLabel: resolvedUnitLabel,
      variants: previous.variants,
    );
    notifyListeners();

    try {
      await _client.from('products').update({
        'name': name,
        'price': price,
        'category_id': categoryId,
        'emoji': trimmedEmoji,
        'track_stock': resolvedTrackStock,
        'unit': resolvedUnit,
        'unit_label': resolvedUnitLabel,
      }).eq('id', id);
    } catch (e) {
      _products[index] = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// Reassigns an existing product to a different category — the
  /// missing piece for getting a product out of Uncategorized (there
  /// was previously no way to change a product's category after
  /// creation at all; the only "edit" that existed was
  /// [updateProductImage]). Creates the target category first if it
  /// doesn't exist yet, same as [addProduct] does. Delegates to
  /// [updateProduct] with the product's existing name/price/emoji
  /// unchanged.
  Future<void> updateProductCategory(String id, String newCategory) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final previous = _products[index];
    if (previous.category == newCategory) return;

    await updateProduct(
      id,
      name: previous.name,
      price: previous.price,
      category: newCategory,
      emoji: previous.emoji,
      trackStock: previous.trackStock,
    );
  }

  Future<void> removeProduct(String id) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final removed = _products[index];
    _products.removeAt(index);
    notifyListeners();

    try {
      await _client.from('products').delete().eq('id', id);
    } catch (e) {
      _products.insert(index, removed);
      notifyListeners();
      rethrow;
    }
  }

  /// Adds a size/option to a product (e.g. "Large" for ₱110). Not
  /// optimistic — the row is inserted first so the new variant gets a
  /// real id before it lands in local state, since [updateVariant] and
  /// [deleteVariant] key off that id. Toggling "this product has
  /// sizes" on in the admin UI is just calling this once; the product
  /// itself needs no separate flag (see [Product.hasVariants]).
  ///
  /// Returns the new variant's real id — register_screen.dart needs
  /// this immediately after a brand-new product's sizes save, to
  /// resolve any recipe rows staged against a particular size (see
  /// RecipeEditor.sizes doc) to their real variant_id. Returns '' on
  /// the two early-return paths below (product not found locally /
  /// blank name) — same empty-string "this one failed" convention
  /// register_screen.dart's savedVariantIds list already expects.
  Future<String> addVariant(
    String productId, {
    required String name,
    required double price,
  }) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index < 0) return '';
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return '';

    final currentVariants = _products[index].variants;
    final nextSortOrder = currentVariants.isEmpty
        ? 0
        : currentVariants.map((v) => v.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    final row = await _client
        .from('product_variants')
        .insert({
          'product_id': productId,
          'name': trimmedName,
          'price': price,
          'sort_order': nextSortOrder,
        })
        .select()
        .single();

    final variant = ProductVariant.fromRow(row);
    _products[index] = _products[index].copyWith(
      variants: [...currentVariants, variant],
    );
    notifyListeners();
    return variant.id;
  }

  /// Renames and/or repriced an existing size. Optimistic — the size
  /// list in the admin editor updates instantly, rolled back if the
  /// write fails.
  Future<void> updateVariant(
    String variantId, {
    String? name,
    double? price,
  }) async {
    var productIndex = -1;
    var variantIndex = -1;
    for (var i = 0; i < _products.length; i++) {
      final vi = _products[i].variants.indexWhere((v) => v.id == variantId);
      if (vi >= 0) {
        productIndex = i;
        variantIndex = vi;
        break;
      }
    }
    if (productIndex < 0) return;

    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isEmpty) return;

    final previousVariants = _products[productIndex].variants;
    final previous = previousVariants[variantIndex];
    final updated = previous.copyWith(name: trimmedName, price: price);

    final nextVariants = [...previousVariants];
    nextVariants[variantIndex] = updated;
    _products[productIndex] = _products[productIndex].copyWith(variants: nextVariants);
    notifyListeners();

    try {
      await _client.from('product_variants').update({
        if (trimmedName != null) 'name': trimmedName,
        if (price != null) 'price': price,
      }).eq('id', variantId);
    } catch (e) {
      final rollback = [...previousVariants];
      _products[productIndex] = _products[productIndex].copyWith(variants: rollback);
      notifyListeners();
      rethrow;
    }
  }

  /// Removes a size. Optimistic with rollback, same pattern as
  /// [removeProduct]. Existing sale records keep their
  /// variant_name/variant_id snapshot on transaction_line_items
  /// regardless (variant_id set null via ON DELETE SET NULL, the name
  /// text stays put) — deleting a size never rewrites past receipts.
  Future<void> deleteVariant(String variantId) async {
    var productIndex = -1;
    var variantIndex = -1;
    for (var i = 0; i < _products.length; i++) {
      final vi = _products[i].variants.indexWhere((v) => v.id == variantId);
      if (vi >= 0) {
        productIndex = i;
        variantIndex = vi;
        break;
      }
    }
    if (productIndex < 0) return;

    final previousVariants = _products[productIndex].variants;
    final removed = previousVariants[variantIndex];
    final nextVariants = [...previousVariants]..removeAt(variantIndex);
    _products[productIndex] = _products[productIndex].copyWith(variants: nextVariants);
    notifyListeners();

    try {
      await _client.from('product_variants').delete().eq('id', variantId);
    } catch (e) {
      final rollback = [...nextVariants]..insert(variantIndex, removed);
      _products[productIndex] = _products[productIndex].copyWith(variants: rollback);
      notifyListeners();
      rethrow;
    }
  }

  /// Uploads a new/replacement photo for an existing product and
  /// persists its URL. Call this from the camera badge in edit mode
  /// (ProductCard.onImageSelected). Photo won't show until this
  /// resolves — there's no optimistic local preview here, since the
  /// picker's own loading spinner already covers that gap, and we'd
  /// rather not show a picked photo that then silently fails to save.
  Future<void> updateProductImage(String id, Uint8List imageBytes) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;

    final imageUrl = await _uploadProductImage(id, imageBytes);
    final updated = await _client
        .from('products')
        .update({'image_url': imageUrl})
        .eq('id', id)
        .select();
    if ((updated as List).isEmpty) {
      // RLS blocked the update — Supabase doesn't throw for this, it
      // just matches zero rows and returns success. Without this
      // check, the photo would show in this session (from the local
      // copyWith below) but silently never actually persist, which is
      // exactly the bug that motivated adding this check.
      throw StateError('image_url update matched no rows (RLS?) for product $id');
    }

    _products[index] = _products[index].copyWith(imageUrl: imageUrl);
    notifyListeners();
  }

  Future<void> adjustStock(String id, int delta) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final current = _products[index].stockQty;
    final next = (current + delta) < 0 ? 0 : current + delta;
    return _writeStock(id, index, next);
  }

  Future<void> setStock(String id, int quantity) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    return _writeStock(id, index, quantity < 0 ? 0 : quantity);
  }

  Future<void> _writeStock(String id, int index, int next) async {
    final previous = _products[index].stockQty;
    _products[index] = _products[index].copyWith(stockQty: next);
    notifyListeners();

    try {
      await _client.from('products').update({'stock_qty': next}).eq('id', id);
    } catch (e) {
      _products[index] = _products[index].copyWith(stockQty: previous);
      notifyListeners();
      rethrow;
    }
  }

  /// Deducts stock for a completed sale. Only for products with
  /// [Product.trackStock] on (drinks/cups) — food items you count and
  /// restock by hand are untouched by checkout. Fires one update per
  /// line item — fine at today's single-till sale volume; worth
  /// batching into a single RPC later if that ever becomes a
  /// bottleneck.
  Future<void> deductStockForSale(List<CartItem> soldItems) async {
    for (final item in soldItems) {
      if (!item.product.trackStock) continue;
      await adjustStock(item.product.id, -item.quantity);
    }
  }

  /// Same deduction, but from a queued offline sale's saved
  /// TransactionLineItem snapshots instead of live CartItems — used
  /// when a sale that couldn't reach Supabase at checkout time finally
  /// syncs later. By then there's no CartItem/Product object left,
  /// only the flat sale record TransactionProvider persisted to disk,
  /// so trackStock is looked up from the current catalog by id.
  Future<void> deductStockForLineItems(List<TransactionLineItem> items) async {
    for (final item in items) {
      if (item.productId.isEmpty) continue; // product was deleted before this synced
      final matches = _products.where((p) => p.id == item.productId);
      if (matches.isEmpty || !matches.first.trackStock) continue;
      await adjustStock(item.productId, -item.quantity);
    }
  }

  Future<void> setLowStockThreshold(String id, int threshold) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final clamped = threshold < 0 ? 0 : threshold;
    final previous = _products[index].lowStockThreshold;
    _products[index] = _products[index].copyWith(lowStockThreshold: clamped);
    notifyListeners();

    try {
      await _client.from('products').update({'low_stock_threshold': clamped}).eq('id', id);
    } catch (e) {
      _products[index] = _products[index].copyWith(lowStockThreshold: previous);
      notifyListeners();
      rethrow;
    }
  }
}
