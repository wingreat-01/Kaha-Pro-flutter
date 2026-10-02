import 'product_variant.dart';

/// Every unit a product's stock can be counted in — 'pc' covers
/// today's implicit assumption (drinks, snacks, most retail items);
/// the rest exist for stores that stock/sell by weight, volume, or
/// bulk unit (hardware, groceries, food & beverage supplies). Kept in
/// sync with the `products_unit_check` constraint in
/// 002_add_product_unit.sql — extend both together.
const kProductUnits = ['pc', 'g', 'kg', 'ml', 'L', 'pack', 'sack', 'custom'];

const _kProductUnitLabels = {
  'pc': 'pc',
  'g': 'g',
  'kg': 'kg',
  'ml': 'mL',
  'L': 'L',
  'pack': 'pack',
  'sack': 'sack',
};

class Product {
  final String id;
  final String name;
  final double price;
  final String category;
  final String? emoji; // fallback placeholder art when there's no imageUrl
  final String? imageUrl; // public Supabase Storage URL for the uploaded
                           // product photo, e.g. product-images/{uid}/{id}.jpg
  final int stockQty; // current on-hand count, adjusted via InventoryPanel
                       // or automatically on checkout
  final int lowStockThreshold; // stockQty at/below this shows a LOW badge
  final bool trackStock; // true = stockQty auto-deducts 1 per unit sold at
                          // checkout (drinks/cups); false = stockQty is
                          // manual-only, untouched by sales (e.g. food items
                          // restocked/counted by hand)
  final String unit; // one of kProductUnits — what stockQty is counted in.
                      // 'pc' by default, matching every product's behavior
                      // before this field existed. Deduction math on
                      // checkout is unchanged (still -1 per unit sold) —
                      // this only changes the label, e.g. a hardware store
                      // selling "Cement" per sack still deducts 1 sack per
                      // sale, just displayed as "1 sack" instead of "1 pc".
  final String? unitLabel; // free-text label, only used when unit == 'custom'
                      // (e.g. "roll", "bundle", "meter")
  final double? costPerUnit; // what one unit costs the store (optional) --
                              // e.g. what a bottle of water costs you to
                              // buy. Null = not set yet. Same idea as
                              // Ingredient.costPerUnit.
  final List<ProductVariant> variants; // optional sizes (e.g. Medium/Large/
                          // Grande), each with its own name + price. Empty
                          // by default, meaning the product just uses its
                          // own flat `price` above, unchanged from before
                          // variants existed. Sorted by sortOrder by the
                          // provider on load.
  final bool showOnQrMenu; // owner-controlled: whether this product appears
                          // on the customer-facing QR ordering page.
                          // Independent of stock — an untracked item like
                          // "Chicken Fillet w/ rice" has no meaningful
                          // stockQty and should still be toggleable on its
                          // own. Defaults to true so every existing product
                          // shows up on the QR menu automatically unless the
                          // owner opts it out. get_menu_for_qr additionally
                          // hides a tracked-stock item once stockQty hits 0,
                          // regardless of this flag.

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.emoji,
    this.imageUrl,
    this.stockQty = 0,
    this.lowStockThreshold = 5,
    this.trackStock = false,
    this.unit = 'pc',
    this.unitLabel,
    this.costPerUnit,
    this.variants = const [],
    this.showOnQrMenu = true,
  });

  /// True when at least one size keeps its own stock count (see
  /// [ProductVariant.stockQty]). False for products without sizes and
  /// for products whose sizes all share the product-level count — in
  /// both cases everything behaves exactly as before per-size stock
  /// existed.
  bool get hasVariantStock => variants.any((v) => v.stockQty != null);

  /// True when the product-level [stockQty] still matters: either no
  /// size has its own count, or some sizes don't and draw from it.
  bool get usesSharedStock =>
      !hasVariantStock || variants.any((v) => v.stockQty == null);

  /// Everything on hand for this product — the sum of the per-size
  /// counts plus the shared count when any size still uses it.
  int get totalStock {
    if (!hasVariantStock) return stockQty;
    var total = usesSharedStock ? stockQty : 0;
    for (final v in variants) {
      total += v.stockQty ?? 0;
    }
    return total;
  }

  /// Stock that a sale of [variant] (or of the plain product when null)
  /// would draw from.
  int stockFor(ProductVariant? variant) => variant?.stockQty ?? stockQty;

  /// Low when the product-level count is at/below the threshold, or —
  /// for products with per-size counts — when any individually
  /// tracked size is.
  bool get isLowStock {
    if (!hasVariantStock) return stockQty <= lowStockThreshold;
    for (final v in variants) {
      final q = v.stockQty;
      if (q != null && q <= lowStockThreshold) return true;
    }
    return usesSharedStock && stockQty <= lowStockThreshold;
  }

  /// Tracked product with nothing left anywhere (all sizes combined).
  bool get isSoldOut => trackStock && totalStock <= 0;

  /// Human-readable unit label for display — the custom free-text
  /// label when set, otherwise the standard label for `unit`, falling
  /// back to the raw `unit` string for any value not in the map
  /// (shouldn't happen given the DB check constraint, but keeps this
  /// from silently showing nothing if it ever does).
  String get unitDisplay =>
      unit == 'custom' ? (unitLabel?.trim().isNotEmpty == true ? unitLabel!.trim() : 'pc') : (_kProductUnitLabels[unit] ?? unit);

  /// True when this product should show a size picker instead of adding
  /// straight to cart. False (the common case) means "behaves exactly
  /// like before variants existed."
  bool get hasVariants => variants.isNotEmpty;

  Product copyWith({
    String? name,
    double? price,
    String? category,
    String? emoji,
    String? imageUrl,
    int? stockQty,
    int? lowStockThreshold,
    bool? trackStock,
    String? unit,
    String? unitLabel,
    double? costPerUnit,
    bool clearCostPerUnit = false, // true = set cost back to "not set"
    List<ProductVariant>? variants,
    bool? showOnQrMenu,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      emoji: emoji ?? this.emoji,
      imageUrl: imageUrl ?? this.imageUrl,
      stockQty: stockQty ?? this.stockQty,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      trackStock: trackStock ?? this.trackStock,
      unit: unit ?? this.unit,
      unitLabel: unitLabel ?? this.unitLabel,
      costPerUnit: clearCostPerUnit ? null : (costPerUnit ?? this.costPerUnit),
      variants: variants ?? this.variants,
      showOnQrMenu: showOnQrMenu ?? this.showOnQrMenu,
    );
  }
}
