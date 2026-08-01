class Product {
  final String id;
  final String name;
  final double price;
  final String category;
  final String? emoji; // simple placeholder art until real product images/icons exist

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.emoji,
  });
}
