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

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.emoji,
    this.imageUrl,
    this.stockQty = 0,
    this.lowStockThreshold = 5,
  });

  bool get isLowStock => stockQty <= lowStockThreshold;

  Product copyWith({
    String? name,
    double? price,
    String? category,
    String? emoji,
    String? imageUrl,
    int? stockQty,
    int? lowStockThreshold,
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
    );
  }
}
