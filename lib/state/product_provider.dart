import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/transaction.dart';

/// Product catalog state, backed by Supabase (categories/products
/// tables). Phase D of the Supabase migration — replaces the mock-data
/// seed with a real fetch, scoped to the caller's store via RLS.
///
/// Load pattern: fetch-once-on-login, not realtime. Call
/// [loadFromSupabase] right after a successful sign-in and before
/// showing HomeShell; nothing auto-refreshes after that until the next
/// login (matches today's single-till, single-device usage).
class ProductProvider extends ChangeNotifier {
  static const String uncategorized = 'Uncategorized';

  final SupabaseClient _client = Supabase.instance.client;

  List<Product> _products = [];
  final List<String> _categoryNames = [];

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

  /// Fetches this store's categories and products. Call once, right
  /// after login. Categories load first since products need the
  /// id->name map to reconstruct their category field.
  Future<void> loadFromSupabase() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final categoryRows = await _client
          .from('categories')
          .select('id, name, is_protected')
          .order('created_at');

      _categoryNames.clear();
      _categoryIds.clear();
      for (final row in categoryRows as List) {
        final name = row['name'] as String;
        _categoryNames.add(name);
        _categoryIds[name] = row['id'] as String;
      }

      final productRows = await _client
          .from('products')
          .select('*, categories(name)')
          .order('created_at');

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
    return Product(
      id: row['id'] as String,
      name: row['name'] as String,
      price: (row['price'] as num).toDouble(),
      category: categoryName,
      emoji: row['emoji'] as String?,
      imageBytes: null, // image_path/Storage wiring is Phase H
      stockQty: row['stock_qty'] as int,
      lowStockThreshold: row['low_stock_threshold'] as int,
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

  Future<void> addProduct({
    required String name,
    required double price,
    required String category,
    String? emoji,
    Uint8List? imageBytes,
    int stockQty = 0,
    int lowStockThreshold = 5,
  }) async {
    if (!_categoryNames.contains(category)) {
      await addCategory(category);
    }
    final categoryId = _categoryIds[category];
    if (categoryId == null) return;

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
          })
          .select()
          .single();

      _products.add(Product(
        id: row['id'] as String,
        name: name,
        price: price,
        category: category,
        emoji: (emoji == null || emoji.trim().isEmpty) ? null : emoji.trim(),
        imageBytes: imageBytes, // local only until Phase H (Storage) lands
        stockQty: stockQty,
        lowStockThreshold: lowStockThreshold,
      ));
      notifyListeners();
    } catch (e) {
      rethrow;
    }
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

  /// Local-only for now — Phase H wires this to Supabase Storage
  /// (image_path column + signed URLs, same pattern as UpaPro's
  /// tenant-docs bucket). Photos won't survive a reload until then.
  void updateProductImage(String id, Uint8List? imageBytes) {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _products[index] = _products[index].copyWith(imageBytes: imageBytes);
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

  /// Deducts stock for a completed sale. Fires one update per line item —
  /// fine at today's single-till sale volume; worth batching into a
  /// single RPC later if that ever becomes a bottleneck.
  Future<void> deductStockForSale(List<CartItem> soldItems) async {
    for (final item in soldItems) {
      await adjustStock(item.product.id, -item.quantity);
    }
  }

  /// Same deduction, but from a queued offline sale's saved
  /// TransactionLineItem snapshots instead of live CartItems — used
  /// when a sale that couldn't reach Supabase at checkout time finally
  /// syncs later. By then there's no CartItem/Product object left,
  /// only the flat sale record TransactionProvider persisted to disk.
  Future<void> deductStockForLineItems(List<TransactionLineItem> items) async {
    for (final item in items) {
      if (item.productId.isEmpty) continue; // product was deleted before this synced
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
