import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/store_provider.dart';
import '../state/billing_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';

/// Static plan matrix, mirrors kahapro-subscription-plan.md's Free/
/// Starter/Basic/Pro table. Deliberately hardcoded here rather than
/// fetched -- this screen is a picker, not a source of truth; the
/// real gating logic lives server-side (product_limit(),
/// ai_credit_allotment(), consume_ai_credit()) and doesn't read
/// anything from this file. subscriptionId is null for the Free
/// Trial (not purchasable) and set for Starter/Basic/Pro, matching
/// the product IDs BillingProvider queries from Play Console.
class _PlanInfo {
  final String id; // matches stores.plan values
  final String? subscriptionId; // Play Console subscription product ID, null = not purchasable
  final String name;
  final String monthlyPrice;
  final String? yearlyPrice;
  final List<String> features;
  // Free-trial-only explanatory line shown under its features instead
  // of Choose buttons, since the trial isn't a plan you can select
  // again once it's over (see UpgradeScreen doc comment) -- null for
  // Starter/Basic/Pro, which always get real purchase buttons.
  final String? footnote;

  const _PlanInfo({
    required this.id,
    this.subscriptionId,
    required this.name,
    required this.monthlyPrice,
    this.yearlyPrice,
    required this.features,
    this.footnote,
  });
}

const List<_PlanInfo> _kPlans = [
  _PlanInfo(
    id: 'free',
    name: 'Free Trial',
    monthlyPrice: '₱0',
    yearlyPrice: null,
    // Deliberately mirrors Pro's feature list -- the trial should
    // give full run of the app, not a capped preview, so an owner
    // can actually decide whether it's worth paying for based on
    // real use rather than an artificially limited sample.
    features: [
      'Everything in Pro, on us for 30 days',
      'Unlimited staff accounts',
      'Unlimited transaction history',
      '10 AI assistant credits / month',
      'Unlimited products',
    ],
    footnote: 'One-time trial — pick a plan below once it ends to keep going.',
  ),
  _PlanInfo(
    id: 'starter',
    subscriptionId: kStarterSubscriptionId,
    name: 'Starter',
    monthlyPrice: '₱190/mo',
    yearlyPrice: '₱1,900/yr',
    features: [
      '1 staff account',
      '30 days transaction history',
      '30 AI assistant credits / month',
      'Up to 50 products',
    ],
  ),
  _PlanInfo(
    id: 'basic',
    subscriptionId: kBasicSubscriptionId,
    name: 'Basic',
    monthlyPrice: '₱290/mo',
    yearlyPrice: '₱2,900/yr',
    features: [
      '5 staff accounts',
      '90 days transaction history',
      '50 AI assistant credits / month',
      'Up to 200 products',
    ],
  ),
  _PlanInfo(
    id: 'pro',
    subscriptionId: kProSubscriptionId,
    name: 'Pro',
    monthlyPrice: '₱490/mo',
    yearlyPrice: '₱4,900/yr',
    features: [
      'Unlimited staff accounts',
      'Unlimited transaction history',
      '100 AI assistant credits / month',
      'Unlimited products',
      'Priority support',
    ],
  ),
];

/// Plan picker, reached by tapping the Plan row in Settings. Available
/// any time -- not gated behind an expired trial -- since forcing
/// someone to wait out the full trial before they're even allowed to
/// upgrade just delays them (and delays revenue) for no reason. The
/// trial-expired state is what makes upgrading feel *urgent*, not what
/// makes it *possible*.
///
/// Choosing Monthly or Yearly on a paid plan now launches Google's
/// real purchase sheet via BillingProvider -- there is no more
/// "we'll reach out" placeholder flow. What happens AFTER a purchase
/// comes back as successful (updating stores.plan) still depends on
/// verify-purchase, the server-side Edge Function -- see
/// BillingProvider's class doc comment. BillingProvider.onPlanActivated
/// is wired below (in initState) to StoreProvider.loadFromSupabase, so
/// once verify-purchase confirms the purchase and updates the DB, this
/// screen's "CURRENT PLAN" badge and feature gates elsewhere in the
/// app pick up the new plan without requiring a fresh login.
class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    // BillingProvider is registered once in main.dart's MultiProvider
    // (like PrinterProvider/ThemeProvider) -- init() here is safe to
    // call every time this screen opens; it's cheap to re-run
    // (mostly a product-details re-query) and guarantees products are
    // fresh if this is the first screen that's touched billing this
    // session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kIsWeb) {
        // Play Billing only exists inside the Android Play Store app
        // -- there's no web equivalent, and in_app_purchase_android
        // has no web implementation to even call. Skip init()
        // entirely rather than let isAvailable() throw against a
        // platform channel that doesn't exist here.
        return;
      }
      final billing = context.read<BillingProvider>();
      final store = context.read<StoreProvider>();
      // Capture the StoreProvider instance itself, not context -- a
      // purchase can still be verifying after the user navigates away
      // from this screen (e.g. backgrounds the app during Play's
      // sheet), and StoreProvider outlives this screen for the whole
      // app session, so this stays safe to call whenever
      // verify-purchase actually responds.
      billing.onPlanActivated = () => store.loadFromSupabase();
      billing.init();
    });
  }

  void _maybeShowPurchaseError(BuildContext context, BillingProvider billing) {
    final error = billing.purchaseError;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.ledgerRed),
        );
      });
    } else if (error == null) {
      _lastShownError = null;
    }
  }

  void _choosePeriod(BuildContext context, _PlanInfo plan) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.slate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${plan.name} — choose billing', style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
              const SizedBox(height: 16),
              _PeriodOption(
                label: 'Monthly',
                price: plan.monthlyPrice,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.read<BillingProvider>().buySubscription(plan.subscriptionId!, BillingPeriod.monthly);
                },
              ),
              if (plan.yearlyPrice != null) ...[
                const SizedBox(height: 10),
                _PeriodOption(
                  label: 'Yearly',
                  price: plan.yearlyPrice!,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.read<BillingProvider>().buySubscription(plan.subscriptionId!, BillingPeriod.yearly);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreProvider>().store;
    final billing = context.watch<BillingProvider>();
    if (!kIsWeb) {
      _maybeShowPurchaseError(context, billing);
    }

    // A store manually flipped to the 'expired' testing value (see
    // Store.isExpired) isn't really "on" any real plan -- treat it as
    // free for the purpose of highlighting the current card, same as
    // a genuinely lapsed trial.
    final currentPlanId = (store == null || store.plan == 'expired') ? 'free' : store.plan;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        elevation: 0,
        title: Text('Choose a plan', style: AppTextStyles.mono(size: 15, weight: FontWeight.w700, letterSpacing: 1)),
      ),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (store?.isExpired ?? false) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.ledgerRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.ledgerRed.withOpacity(0.4), width: 1),
                ),
                child: Text(
                  'Your free trial has ended. Pick a plan below to keep going.',
                  style: AppTextStyles.body(size: 13, weight: FontWeight.w600, color: AppColors.ledgerRed),
                ),
              ),
            ],
            if (kIsWeb) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Upgrading is available in the MERQ Android app.',
                  style: AppTextStyles.body(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ),
            ],
            if (!kIsWeb && billing.loadError != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(billing.loadError!, style: AppTextStyles.body(size: 12, color: AppColors.textMuted)),
              ),
            ],
            for (final plan in _kPlans)
              _PlanCard(
                plan: plan,
                isCurrent: plan.id == currentPlanId,
                purchaseInProgress: billing.purchaseInProgress,
                isWeb: kIsWeb,
                onChoosePeriod: () => _choosePeriod(context, plan),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodOption extends StatelessWidget {
  final String label;
  final String price;
  final VoidCallback onTap;

  const _PeriodOption({required this.label, required this.price, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.slateBorder, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
            Text(price, style: AppTextStyles.mono(size: 14, weight: FontWeight.w700, color: AppColors.ledAmber)),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _PlanInfo plan;
  final bool isCurrent;
  final bool purchaseInProgress;
  final bool isWeb;
  final VoidCallback onChoosePeriod;

  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.purchaseInProgress,
    required this.isWeb,
    required this.onChoosePeriod,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? AppColors.ledAmber : AppColors.slateBorder,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(plan.name, style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
              const SizedBox(width: 10),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.ledAmber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'CURRENT PLAN',
                    style: AppTextStyles.mono(size: 9.5, weight: FontWeight.w700, color: AppColors.ledAmber, letterSpacing: 1),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(plan.monthlyPrice, style: AppTextStyles.mono(size: 20, weight: FontWeight.w700, color: AppColors.ledAmber)),
              if (plan.yearlyPrice != null) ...[
                const SizedBox(width: 8),
                Text('or ${plan.yearlyPrice}', style: AppTextStyles.body(size: 12, color: AppColors.textMuted)),
              ] else if (plan.id == 'free') ...[
                const SizedBox(width: 8),
                Text('for 30 days', style: AppTextStyles.body(size: 12, color: AppColors.textMuted)),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 15, color: AppColors.tillGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(feature, style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (isCurrent)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null,
                child: Text('Current plan', style: AppTextStyles.body(size: 13, weight: FontWeight.w700)),
              ),
            )
          else if (plan.footnote != null)
            // Free trial, not currently on it -- no purchase button;
            // it's a one-time onboarding period, not a plan you can
            // switch back to (see UpgradeScreen doc comment).
            Text(plan.footnote!, style: AppTextStyles.body(size: 12, color: AppColors.textMuted))
          else if (isWeb)
            // No Play Billing equivalent exists on web -- showing a
            // disabled/dead Choose button would look broken rather
            // than explain why nothing happens when tapped.
            Text(
              'Available in the Android app',
              style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: purchaseInProgress ? null : onChoosePeriod,
                child: purchaseInProgress
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Choose ${plan.name}', style: AppTextStyles.body(size: 13, weight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}
