/// The signed-in owner's store. Currently just enough to drive the
/// Inventory screen's label (see kahapro-inventory-recipes-plan.md
/// Step 0) -- id/name/businessType -- plus plan + AI credit state used
/// by Settings, the Upgrade screen, and the AI Assistant tab.
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
  final int aiCreditsRemaining; // this cycle's remaining AI Assistant credits
  final DateTime? aiCreditsResetAt; // when the monthly credit count next resets

  const Store({
    required this.id,
    required this.name,
    required this.businessType,
    required this.plan,
    this.planExpiresAt,
    this.aiCreditsRemaining = 0,
    this.aiCreditsResetAt,
  });

  factory Store.fromRow(Map<String, dynamic> row) {
    final expiresRaw = row['plan_expires_at'] as String?;
    final creditsResetRaw = row['ai_credits_reset_at'] as String?;
    return Store(
      id: row['id'] as String,
      name: row['name'] as String,
      businessType: row['business_type'] as String? ?? 'general',
      plan: row['plan'] as String? ?? 'free',
      planExpiresAt: expiresRaw != null ? DateTime.parse(expiresRaw) : null,
      aiCreditsRemaining: (row['ai_credits_remaining'] as num?)?.toInt() ?? 0,
      aiCreditsResetAt: creditsResetRaw != null ? DateTime.parse(creditsResetRaw) : null,
    );
  }

  /// Used for the optimistic local decrement right after a successful
  /// AI Assistant reply (see StoreProvider.decrementAiCredit) -- avoids
  /// an extra round trip just to refresh a number the edge function
  /// already updated server-side.
  Store copyWith({int? aiCreditsRemaining}) => Store(
        id: id,
        name: name,
        businessType: businessType,
        plan: plan,
        planExpiresAt: planExpiresAt,
        aiCreditsRemaining: aiCreditsRemaining ?? this.aiCreditsRemaining,
        aiCreditsResetAt: aiCreditsResetAt,
      );

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
  int? get trialDaysRemaining {
    if (planExpiresAt == null) return null;
    final remaining = planExpiresAt!.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  /// True when the AI Assistant tab's input should be usable -- store
  /// isn't expired AND has at least one credit left this cycle. Mirrors
  /// has_ai_credit() server-side, but this is UX only: the edge
  /// function is still the real enforcement (see kahapro-subscription-
  /// plan.md -- Flutter checks are convenience, not security).
  bool get canUseAiAssistant => !isExpired && aiCreditsRemaining > 0;

  /// The label used everywhere this section is referenced — the
  /// Settings row, the panel's own title, and empty-state copy. Used
  /// to differentiate by business_type (Ingredients/Supplies/Raw
  /// Materials), but a single store commonly stocks both food
  /// ingredients AND packaging supplies (cups, straws, thermal paper,
  /// stickers, clamshells) side by side — so one broad label covers
  /// all business types now instead of forking on business_type.
  String get businessTypeLabel => 'Supplies & Materials';
}
