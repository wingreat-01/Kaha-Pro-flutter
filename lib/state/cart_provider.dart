import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variant.dart';

/// Cart state for the Register screen. Wrap the app with
/// ChangeNotifierProvider<CartProvider> in main.dart to use this.
///
/// Phase E: the cart is now persisted to disk (SharedPreferences) on
/// every mutation, so an accidental app close/crash mid-sale doesn't
/// silently drop whatever was already in the cart. Only productId +
/// variantId + quantity are saved — not a full Product/Variant
/// snapshot — because a saved cart is only meaningful once matched
/// back against the current product catalog (see restoreFromDisk): a
/// stale cached price, a product that got deleted, or a size that got
/// deleted while the app was closed shouldn't get resurrected into an
/// active sale.
///
/// A cart line is identified by (productId, variantId) together, not
/// productId alone — "Coffee (Medium)" and "Coffee (Large)" are
/// separate lines. variantId is null for every product without sizes,
/// which is exactly today's single-line-per-product behavior.
class CartProvider extends ChangeNotifier {
  static const _cartStorageKey = 'kahapro_cart_items';

  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0, (sum, item) => sum + item.lineTotal);

  // No tax/discount logic yet — total mirrors subtotal until checkout
  // rules are defined in Pass C / Phase 3.
  double get total => subtotal;

  int _matchIndex(String productId, String? variantId) {
    return _items.indexWhere((item) =>
        item.product.id == productId && item.selectedVariant?.id == variantId);
  }

  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items
        .map((item) => {
              'productId': item.product.id,
              'variantId': item.selectedVariant?.id,
              'quantity': item.quantity,
            })
        .toList());
    await prefs.setString(_cartStorageKey, encoded);
  }

  /// Restores a cart left over from a previous session (app closed or
  /// crashed with items still in the cart), matched against the
  /// now-loaded product catalog. Call this once per login, right after
  /// ProductProvider.loadFromSupabase() resolves — see login_screen.dart.
  ///
  /// A saved line whose product no longer exists (deleted while the
  /// app was closed) is silently dropped rather than restored as a
  /// broken cart entry. Same for a line whose saved variantId no
  /// longer exists on that product (the size was renamed away/deleted)
  /// — dropped rather than guessing at a price. Any parse failure
  /// (corrupt/old-format cached data) is treated the same way: start
  /// with an empty cart rather than fail login over a bad local cache.
  Future<void> restoreFromDisk(List<Product> catalog) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cartStorageKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List;
      final restored = <CartItem>[];
      for (final entry in decoded) {
        final map = entry as Map<String, dynamic>;
        final productId = map['productId'] as String;
        final variantId = map['variantId'] as String?;
        final quantity = map['quantity'] as int;
        if (quantity <= 0) continue;

        Product? product;
        for (final p in catalog) {
          if (p.id == productId) {
            product = p;
            break;
          }
        }
        if (product == null) continue; // deleted since the cart was saved

        ProductVariant? variant;
        if (variantId != null) {
          for (final v in product.variants) {
            if (v.id == variantId) {
              variant = v;
              break;
            }
          }
          if (variant == null) continue; // size deleted since the cart was saved
        }

        restored.add(CartItem(product: product, selectedVariant: variant)
          ..quantity = quantity);
      }

      if (restored.isEmpty) return;
      _items
        ..clear()
        ..addAll(restored);
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider.restoreFromDisk: discarding unreadable cached cart: $e');
    }
  }

  /// Adds a product to the cart. Pass [variant] for a product with
  /// sizes (Product.hasVariants) — the Register screen's size picker
  /// supplies this; a plain product tap omits it, same as before.
  void add(Product product, {ProductVariant? variant}) {
    final index = _matchIndex(product.id, variant?.id);
    if (index >= 0) {
      _items[index].quantity += 1;
    } else {
      _items.add(CartItem(product: product, selectedVariant: variant));
    }
    notifyListeners();
    unawaited(_saveToDisk());
  }

  void increment(String productId, {String? variantId}) {
    final index = _matchIndex(productId, variantId);
    if (index >= 0) {
      _items[index].quantity += 1;
      notifyListeners();
      unawaited(_saveToDisk());
    }
  }

  void decrement(String productId, {String? variantId}) {
    final index = _matchIndex(productId, variantId);
    if (index < 0) return;
    if (_items[index].quantity <= 1) {
      _items.removeAt(index);
    } else {
      _items[index].quantity -= 1;
    }
    notifyListeners();
    unawaited(_saveToDisk());
  }

  void remove(String productId, {String? variantId}) {
    _items.removeWhere((item) =>
        item.product.id == productId && item.selectedVariant?.id == variantId);
    notifyListeners();
    unawaited(_saveToDisk());
  }

  void clear() {
    _items.clear();
    notifyListeners();
    unawaited(_saveToDisk());
  }
}
