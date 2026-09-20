import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscription product IDs -- these must exactly match the
/// Subscription IDs you create in Play Console under
/// Monetize > Subscriptions. One subscription product per plan tier
/// (Starter/Basic/Pro), each with two base plans (monthly/yearly)
/// rather than six separate products -- this matches how Play
/// Billing Library 8 models "same product, different billing
/// period" and lets Play Console show renewals/upgrades correctly
/// within one product instead of treating monthly and yearly as
/// totally unrelated purchases.
///
/// RENAME THESE if you create different IDs in Play Console -- these
/// are placeholder names, not fetched from anywhere.
const String kStarterSubscriptionId = 'merq_starter';
const String kBasicSubscriptionId = 'merq_basic';
const String kProSubscriptionId = 'merq_pro';

const List<String> kAllSubscriptionIds = [
  kStarterSubscriptionId,
  kBasicSubscriptionId,
  kProSubscriptionId,
];

/// Base plan IDs within each subscription product above -- same two
/// names reused across all three products, matching whatever you
/// name the base plans in Play Console for each one.
const String kMonthlyBasePlanId = 'monthly';
const String kYearlyBasePlanId = 'yearly';

enum BillingPeriod { monthly, yearly }

/// Wraps the in_app_purchase plugin for MERQ's three paid plans.
///
/// The in_app_purchase plugin can launch Google's purchase sheet and
/// tell you a purchase came back as "purchased", but that alone
/// isn't proof the purchase is real -- [_verifyAndActivate] sends the
/// purchase token to the verify-purchase Supabase Edge Function,
/// which checks it against the Play Developer API and only then
/// updates stores.plan / ai_credits_remaining server-side. Local
/// state (e.g. StoreProvider) should be refreshed only after that
/// call succeeds, never on the strength of the client-side
/// "purchased" status by itself.
class BillingProvider extends ChangeNotifier {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool isAvailable = false;
  bool isLoadingProducts = false;
  String? loadError;

  /// Keyed by subscription product ID (kStarterSubscriptionId, etc).
  Map<String, ProductDetails> products = {};

  /// True while a purchase sheet is open or a purchase is being
  /// processed -- lets UpgradeScreen disable its Choose buttons so a
  /// second tap can't launch two purchase flows at once.
  bool purchaseInProgress = false;
  String? purchaseError;

  /// Optional hook set by whoever constructs this provider (e.g.
  /// main.dart's MultiProvider setup), called after verify-purchase
  /// confirms a purchase and the DB has been updated -- wire this to
  /// whatever makes StoreProvider re-fetch the store row, so the UI
  /// picks up the new plan without waiting on its own poll/refresh
  /// cycle. Safe to leave unset; the DB update still happens either
  /// way, this just controls how fast the UI reflects it.
  Future<void> Function()? onPlanActivated;

  Future<void> init() async {
    isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      loadError = 'In-app purchases are not available on this device.';
      notifyListeners();
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (e) {
        purchaseError = 'Purchase stream error: $e';
        purchaseInProgress = false;
        notifyListeners();
      },
    );

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    isLoadingProducts = true;
    loadError = null;
    notifyListeners();

    final response = await _iap.queryProductDetails(kAllSubscriptionIds.toSet());
    if (response.error != null) {
      loadError = response.error!.message;
    }
    if (response.notFoundIDs.isNotEmpty) {
      // Any ID here means it doesn't exist yet in Play Console (or
      // this build isn't running on a track where it's active) --
      // not a crash, just means that plan's card won't be
      // purchasable until it's set up on the Play Console side.
      debugPrint('BillingProvider: product IDs not found in Play Console: ${response.notFoundIDs}');
    }
    products = {for (final p in response.productDetails) p.id: p};

    isLoadingProducts = false;
    notifyListeners();
  }

  /// Finds the offerToken for [basePlanId] within [product]'s
  /// available offers -- required by GooglePlayPurchaseParam to tell
  /// Play which billing period (monthly vs yearly) was chosen, since
  /// a single subscription product can have several base plans.
  /// Returns null if that base plan isn't configured for this
  /// product in Play Console yet (e.g. yearly not set up).
  String? _offerTokenFor(ProductDetails product, String basePlanId) {
    if (product is! GooglePlayProductDetails) return null;
    for (final offer in product.productDetails.subscriptionOfferDetails ?? const []) {
      if (offer.basePlanId == basePlanId) return offer.offerToken;
    }
    return null;
  }

  /// Launches Google's native purchase sheet for [subscriptionId] at
  /// [period]. Does NOT return whether the purchase succeeded --
  /// that comes back asynchronously via the purchaseStream listener
  /// (_onPurchaseUpdate), same as every in_app_purchase flow. UI
  /// should watch [purchaseInProgress]/[purchaseError] rather than
  /// awaiting this for a result.
  Future<void> buySubscription(String subscriptionId, BillingPeriod period) async {
    final product = products[subscriptionId];
    if (product == null) {
      purchaseError = 'This plan is not available for purchase right now.';
      notifyListeners();
      return;
    }

    final basePlanId = period == BillingPeriod.monthly ? kMonthlyBasePlanId : kYearlyBasePlanId;
    final offerToken = _offerTokenFor(product, basePlanId);
    if (offerToken == null) {
      purchaseError = 'That billing period is not set up for this plan yet.';
      notifyListeners();
      return;
    }

    purchaseError = null;
    purchaseInProgress = true;
    notifyListeners();

    final purchaseParam = GooglePlayPurchaseParam(
      productDetails: product,
      offerToken: offerToken,
    );

    // Subscriptions go through buyNonConsumable -- Play itself
    // manages renewal, this call only ever represents the initial
    // "start this subscription" action, not a repeated purchase.
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Required by Play policy (subscriptions must be restorable, e.g.
  /// after a reinstall) -- not wired to a button anywhere yet. Add a
  /// "Restore purchases" action wherever makes sense once the server
  /// side exists to actually act on what comes back.
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          purchaseInProgress = true;
          break;

        case PurchaseStatus.error:
          purchaseInProgress = false;
          purchaseError = purchase.error?.message ?? 'Purchase failed.';
          break;

        case PurchaseStatus.canceled:
          purchaseInProgress = false;
          purchaseError = null; // user backed out -- not a real error
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Left true until _verifyAndActivate finishes -- the
          // purchase sheet closing isn't the point where the UI
          // should re-enable Choose buttons; the plan hasn't
          // actually changed until the server confirms it.
          unawaited(_verifyAndActivate(purchase));
          break;
      }

      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  /// Sends the purchase token to the verify-purchase Edge Function,
  /// which checks it against the Play Developer API and, if valid,
  /// updates stores.plan / ai_credits_remaining server-side. Only on
  /// a successful response do we call [onPlanActivated] -- the
  /// client-side "purchased" status from Play is never treated as
  /// proof by itself that the plan actually changed.
  Future<void> _verifyAndActivate(PurchaseDetails purchase) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'verify-purchase',
        body: {
          'productId': purchase.productID,
          'purchaseToken': purchase.verificationData.serverVerificationData,
        },
      );

      if (response.status != 200) {
        final message = response.data is Map ? response.data['error'] : null;
        purchaseError = message?.toString() ?? 'Could not verify your purchase. Please contact support.';
        debugPrint('verify-purchase failed (${response.status}): ${response.data}');
      } else {
        purchaseError = null;
        if (onPlanActivated != null) {
          await onPlanActivated!();
        }
      }
    } catch (e) {
      purchaseError = 'Could not verify your purchase: $e';
      debugPrint('verify-purchase threw: $e');
    } finally {
      purchaseInProgress = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
