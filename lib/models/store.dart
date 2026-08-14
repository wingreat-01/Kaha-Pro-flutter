/// The signed-in owner's store. Currently just enough to drive the
/// Inventory screen's label (see kahapro-inventory-recipes-plan.md
/// Step 0) -- id/name/businessType. Grow this as more store-level
/// settings need a typed home instead of ad hoc Supabase queries.
class Store {
  final String id;
  final String name;
  final String businessType; // 'food_beverage' | 'retail_hardware' | 'general'
  final String plan; // 'free' | 'basic' | 'pro' | 'expired' (manual testing value, see below)
  final DateTime? planExpiresAt; // real trial end date -- 15 days from
                          // creation for free-plan stores, set server-side
                          // by the trg_set_default_trial_expiry trigger
                          // (006_add_trial_expiry.sql). Null for paid
                          // plans or a store this trigger hasn't touched.

  const Store({
    required this.id,
    required this.name,
    required this.businessType,
    required this.plan,
    this.planExpiresAt,
  });

  factory Store.fromRow(Map<String, dynamic> row) {
    final expiresRaw = row['plan_expires_at'] as String?;
    return Store(
      id: row['id'] as String,
      name: row['name'] as String,
      businessType: row['business_type'] as String? ?? 'general',
      plan: row['plan'] as String? ?? 'free',
      planExpiresAt: expiresRaw != null ? DateTime.parse(expiresRaw) : null,
    );
  }

  /// True when the trial-expired banner/lock should show. Two paths:
  ///  - plan == 'expired': the manual testing override (see
  ///    kahapro-subscription-plan.md) -- flip a store to this string
  ///    via SQL to see the expired state without waiting 15 real days.
  ///  - plan_expires_at has actually passed: the real trial check,
  ///    once 006_add_trial_expiry.sql's trigger has set a date.
  /// A paid plan (basic/pro) never has plan_expires_at set by that
  /// trigger, so this stays false for a paying store regardless of
  /// how old the account is.
  bool get isExpired =>
      plan == 'expired' ||
      (planExpiresAt != null && planExpiresAt!.isBefore(DateTime.now()));

  /// Whole days left in the trial, floored at 0. Null when there's no
  /// expiry date to count down (paid plan, or not yet backfilled).
  /// Not shown anywhere yet -- available for a future "3 days left"
  /// banner variant.
  int? get trialDaysRemaining {
    if (planExpiresAt == null) return null;
    final remaining = planExpiresAt!.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

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
