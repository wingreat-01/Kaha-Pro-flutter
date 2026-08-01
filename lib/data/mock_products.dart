import '../models/product.dart';

/// Placeholder catalog for Phase 2 layout work.
/// Swap for real inventory data once the Inventory panel (Phase 3) is wired up.

const List<String> mockCategories = [
  'All',
  'Drinks',
  'Add-ons',
];

const List<Product> mockProducts = [
  Product(id: 'p1', name: 'Bottled Water', price: 20, category: 'Drinks', emoji: '💧'),
  Product(id: 'p2', name: 'Soda Can', price: 35, category: 'Drinks', emoji: '🥤'),
  Product(id: 'p3', name: 'Iced Coffee', price: 45, category: 'Drinks', emoji: '☕'),
  Product(id: 'p10', name: 'Extra Rice', price: 15, category: 'Add-ons', emoji: '🍚'),
  Product(id: 'p11', name: 'Extra Sauce', price: 10, category: 'Add-ons', emoji: '🥫'),
  Product(id: 'p12', name: 'Plastic Bag', price: 3, category: 'Add-ons', emoji: '🛍️'),
];
