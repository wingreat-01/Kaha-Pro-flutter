import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

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
/// This is CLIENT-SIDE ONLY. It can launch Google's purchase sheet
/// and tell you a purchase came back as "purchased", but it cannot
/// by itself prove the purchase is real or safely update
/// stores.plan/ai_credits_remaining -- that's the job of a separate
/// Supabase Edge Function (server side, not built yet) that this
/// provider will call once a purchase comes back, passing along the
/// purchase token for verification against the Play Developer API.
/// Until that function exists, [_verifyAndActivate] is a stub that
/// only logs -- see its doc comment for what it needs to do once the
/// server side lands.
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
    for (final offer in product.subscriptionOfferDetails ?? const []) {
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
          _verifyAndActivate(purchase);
          purchaseInProgress = false;
          break;
      }

      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  /// STUB -- server side not built yet. Once the Supabase Edge
  /// Function exists, this should:
  ///   1. POST purchase.verificationData.serverVerificationData (the
  ///      purchase token) and purchase.productID to that function
  ///   2. The function verifies the token against the Play Developer
  ///      API and updates stores.plan / ai_credits_remaining
  ///   3. Only on a verified response should local state (e.g.
  ///      StoreProvider) be told to reload -- don't treat the local
  ///      "purchased" status alone as proof the plan actually changed
  ///
  /// For now this just logs, so the purchase flow can be exercised
  /// end-to-end in the Play Console sandbox (License Testers) without
  /// the plan actually changing yet -- that gap is expected until the
  /// server half is built, not a bug in this stub.
  Future<void> _verifyAndActivate(PurchaseDetails purchase) async {
    debugPrint(
      'TODO: verify purchase server-side. '
      'productId=${purchase.productID}, '
      'token=${purchase.verificationData.serverVerificationData}',
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
