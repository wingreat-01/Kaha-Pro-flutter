import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
// ReplacementMode and ChangeSubscriptionParam live in this sub-library,
// not the main in_app_purchase_android.dart entry point above -- that
// main file covers GooglePlayPurchaseParam/GooglePlayProductDetails,
// but the older "billing_client_wrappers" classes need this explicit
// import or they're simply not visible, which is what caused
// "The getter 'ReplacementMode' isn't defined" at compile time.
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
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

  /// The user's currently known active subscription(s), keyed by
  /// product ID -- populated whenever a purchase for one of
  /// kAllSubscriptionIds comes back as purchased/restored (see
  /// _onPurchaseUpdate), including via restorePurchases(). This is
  /// what lets buySubscription tell Play "replace this existing
  /// subscription" instead of launching an entirely independent
  /// purchase -- without it, switching from e.g. Starter to Pro
  /// bought a second, parallel subscription rather than upgrading,
  /// which is what happened during testing before this was added.
  final Map<String, GooglePlayPurchaseDetails> _activeSubscriptions = {};

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

  /// True only for a short window after the person taps Restore.
  /// Restored purchases are otherwise tracked locally (for the
  /// upgrade/downgrade detection in buySubscription) but NOT sent to
  /// verify-purchase. A Google Play subscription belongs to a Google
  /// account, not to a MERQ store -- so automatically verifying every
  /// restored purchase on screen open handed the same subscription to
  /// whichever store happened to be signed in, and opening the plan
  /// screen on a brand-new store flipped it to the paid plan.
  bool _verifyRestored = false;

  Future<void> init() async {
    isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      loadError = 'In-app purchases are not available on this device.';
      notifyListeners();
      return;
    }

    // init() runs every time UpgradeScreen opens. Assigning a new
    // listener each time without cancelling the old one meant every
    // purchase event was handled once per screen visit. ??= keeps
    // exactly one listener for the life of the provider.
    _subscription ??= _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () {
        _subscription?.cancel();
        _subscription = null;
      },
      onError: (e) {
        purchaseError = 'Purchase stream error: $e';
        purchaseInProgress = false;
        notifyListeners();
      },
    );

    await _loadProducts();

    // Populates _activeSubscriptions with whatever the user already
    // owns, so buySubscription's upgrade/downgrade detection works
    // from the moment this screen opens -- not only after someone
    // manually taps Restore. This is the same restorePurchases() call
    // the Restore button uses; running it here too just means the
    // common case (switching tiers) doesn't depend on a manual step.
    // Calls the plugin directly (not restorePurchases() below) so this
    // automatic pass only fills _activeSubscriptions and never sends
    // tokens to verify-purchase -- see _verifyRestored.
    await _iap.restorePurchases();
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
      // SubscriptionOfferDetailsWrapper's field is named offerIdToken in
      // this package version -- there is no offerToken getter on this
      // class (that name belongs to GooglePlayPurchaseParam/
      // GooglePlayProductDetails instead, which is a separate class).
      // Calling offer.offerToken here threw a NoSuchMethodError
      // synchronously inside the tap handler, before buySubscription's
      // own error handling ever got a chance to run.
      if (offer.basePlanId == basePlanId) return offer.offerIdToken;
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

    // If the user already has an active subscription to a DIFFERENT
    // tier (Starter/Basic/Pro are separate Play Console products, not
    // base plans of one product -- see kAllSubscriptionIds doc
    // comment), this purchase needs to tell Play to replace it.
    // Without changeSubscriptionParam, Play treats this as a
    // brand-new, unrelated purchase and the user ends up with BOTH
    // subscriptions active and billing in parallel -- exactly what
    // happened when this wasn't wired up. withTimeProration credits
    // the remaining time on the old plan toward the new one, which
    // is Play's own recommended default for this kind of tier
    // change.
    //
    // If the same product's purchase happens to be in
    // _activeSubscriptions (e.g. switching monthly -> yearly within
    // the same tier), that's excluded here since Play already
    // handles a same-product base-plan change as a normal purchase
    // via offerToken alone.
    GooglePlayPurchaseDetails? existingPurchase;
    for (final entry in _activeSubscriptions.entries) {
      if (entry.key != subscriptionId) {
        existingPurchase = entry.value;
        break;
      }
    }

    final purchaseParam = GooglePlayPurchaseParam(
      productDetails: product,
      offerToken: offerToken,
      changeSubscriptionParam: existingPurchase != null
          ? ChangeSubscriptionParam(
              oldPurchaseDetails: existingPurchase,
              replacementMode: ReplacementMode.withTimeProration,
            )
          : null,
    );

    // Subscriptions go through buyNonConsumable -- Play itself
    // manages renewal, this call only ever represents the initial
    // "start this subscription" action, not a repeated purchase.
    //
    // This call can throw a PlatformException directly (e.g.
    // developer error, item unavailable, billing service
    // disconnected) rather than reporting failure through
    // purchaseStream/_onPurchaseUpdate like a normal declined
    // purchase does. Without this try/catch, that exception was
    // unhandled: purchaseInProgress stayed true forever and
    // purchaseError was never set, so the UI just looked stuck with
    // no error shown.
    try {
      // buyNonConsumable's bool return says whether the purchase
      // flow actually launched -- NOT whether the purchase itself
      // succeeded (that part really does only come via
      // purchaseStream, per the doc comment above). false here means
      // Play Billing rejected launching the sheet at all (e.g.
      // billing client not ready/connected), which was previously
      // ignored entirely -- purchaseInProgress stayed true forever
      // and no error was ever shown, with the purchase sheet just
      // never appearing.
      final launched = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!launched) {
        purchaseError = 'Could not open the purchase screen. Please try again.';
        purchaseInProgress = false;
        notifyListeners();
      }
    } catch (e) {
      purchaseError = 'Could not start the purchase: $e';
      purchaseInProgress = false;
      notifyListeners();
    }
  }

  /// Required by Play policy (subscriptions must be restorable, e.g.
  /// after a reinstall) -- wired to the "Restore" button in
  /// UpgradeScreen's app bar. Also doubles as how _activeSubscriptions
  /// gets populated on a fresh app install/session (before that, it
  /// only knows about purchases made during buySubscription calls in
  /// the current session), which matters for buySubscription's
  /// upgrade/downgrade detection above.
  Future<void> restorePurchases() async {
    // Explicit tap on the Restore button: this is the only path where
    // restored purchases are verified. The server must still refuse a
    // token that is already linked to a different store.
    _verifyRestored = true;
    try {
      await _iap.restorePurchases();
    } finally {
      // Restored purchases arrive on the stream shortly after the call
      // returns, so keep the flag on briefly before switching it off.
      Future.delayed(const Duration(seconds: 10), () => _verifyRestored = false);
    }
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
          // Track this as the user's active purchase for this
          // product, so a future buySubscription call for a
          // different tier can pass it as the subscription to
          // replace. Only GooglePlayPurchaseDetails carries what
          // ChangeSubscriptionParam needs -- on this Android-only
          // billing provider that's always what purchaseStream
          // hands back, but the check keeps this safe if that ever
          // changes.
          if (purchase is GooglePlayPurchaseDetails && kAllSubscriptionIds.contains(purchase.productID)) {
            _activeSubscriptions[purchase.productID] = purchase;
          }
          // Left true until _verifyAndActivate finishes -- the
          // purchase sheet closing isn't the point where the UI
          // should re-enable Choose buttons; the plan hasn't
          // actually changed until the server confirms it.
          if (purchase.status == PurchaseStatus.purchased || _verifyRestored) {
            unawaited(_verifyAndActivate(purchase));
          }
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
    // Play can report events that aren't a real purchase (a dismissed
    // or failed purchase sheet, an empty restore) with a blank token.
    // There is nothing to verify, and sending it only produced a
    // confusing "Missing purchaseToken" error for the person.
    if (purchase.verificationData.serverVerificationData.isEmpty) {
      debugPrint('BillingProvider: skipped verify for ${purchase.status} event with no purchase token');
      purchaseInProgress = false;
      notifyListeners();
      return;
    }

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
    } on FunctionException catch (e) {
      // functions.invoke THROWS on any non-2xx reply instead of
      // returning it, so the status check above never sees errors.
      // Show the server's own message (e.g. "This subscription is
      // already linked to another store.") instead of the raw
      // exception text.
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      purchaseError = message?.toString() ?? 'Could not verify your purchase. Please try again.';
      debugPrint('verify-purchase failed (${e.status}): ${e.details}');
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
