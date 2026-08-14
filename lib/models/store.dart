/// The signed-in owner's store. Currently just enough to drive the
/// Inventory screen's label (see kahapro-inventory-recipes-plan.md
/// Step 0) -- id/name/businessType. Grow this as more store-level
/// settings need a typed home instead of ad hoc Supabase queries.
class Store {
  final String id;
  final String name;
  final String businessType; // 'food_beverage' | 'retail_hardware' | 'general'
  final String plan; // 'free' | 'expired' | ... (testing uses 'expired' directly)

  const Store({
    required this.id,
    required this.name,
    required this.businessType,
    required this.plan,
  });

  factory Store.fromRow(Map<String, dynamic> row) {
    return Store(
      id: row['id'] as String,
      name: row['name'] as String,
      businessType: row['business_type'] as String? ?? 'general',
      plan: row['plan'] as String? ?? 'free',
    );
  }

  /// Simple string-check gate for testing the trial-expired banner --
  /// no date column, no null-handling. Flip via manual SQL:
  ///   UPDATE stores SET plan = 'expired' WHERE id = '...';
  bool get isExpired => plan == 'expired';

  /// The Step 0 label table: what the Inventory screen (and any
  /// "+ Add ___" button / empty-state copy pulling from it) should
  /// call raw-material items for this store's business type.
  String get businessTypeLabel {
    switch (businessType) {
      case 'food_beverage':
        return 'Ingredients';
      case 'retail_hardware':
        return 'Supplies';
      default:
        return 'Raw Materials';
    }
  }
}
