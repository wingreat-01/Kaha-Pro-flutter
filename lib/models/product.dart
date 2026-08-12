import 'product_variant.dart';

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
    this.variants = const [],
  });

  bool get isLowStock => stockQty <= lowStockThreshold;

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
      variants: variants ?? this.variants,
    );
  }
}
