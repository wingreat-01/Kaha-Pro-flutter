import 'dart:typed_data';

class Product {
  final String id;
  final String name;
  final double price;
  final String category;
  final String? emoji; // fallback placeholder art when there's no imageBytes
  final Uint8List? imageBytes; // user-uploaded product photo, in-memory for
                                // now — move to Supabase Storage once that
                                // integration lands (see migration plan)

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.emoji,
    this.imageBytes,
  });

  Product copyWith({
    String? name,
    double? price,
    String? category,
    String? emoji,
    Uint8List? imageBytes,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      emoji: emoji ?? this.emoji,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }
}
