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
  final List<ProductVariant> variants; // optional sizes (e.g. Medium/Large/
                          // Grande), each with its own name + price. Empty
                          // by default, meaning the product just uses its
                          // own flat `price` above, unchanged from before
                          // variants existed. Sorted by sortOrder by the
                          // provider on load.

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
    this.variants = const [],
  });

  bool get isLowStock => stockQty <= lowStockThreshold;

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
    List<ProductVariant>? variants,
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
      variants: variants ?? this.variants,
    );
  }
}
