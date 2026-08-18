import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/store_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';

/// Static plan matrix, mirrors kahapro-subscription-plan.md's Free/
/// Basic/Pro table. Deliberately hardcoded here rather than fetched --
/// this screen is a picker, not a source of truth; the real gating
/// logic lives server-side (current_store_plan(), consume_ai_credit())
/// and doesn't read anything from this file.
class _PlanInfo {
  final String id; // matches stores.plan values
  final String name;
  final String price;
  final String? priceNote;
  final List<String> features;
  // Free-trial-only explanatory line shown under its features instead
  // of a "Choose" button, since the trial isn't a plan you can select
  // again once it's over (see UpgradeScreen doc comment) -- null for
  // Basic/Pro, which always get a normal Choose button.
  final String? footnote;

  const _PlanInfo({
    required this.id,
    required this.name,
    required this.price,
    this.priceNote,
    required this.features,
    this.footnote,
  });
}

const List<_PlanInfo> _kPlans = [
  _PlanInfo(
    id: 'free',
    name: 'Free Trial',
    price: '₱0',
    priceNote: 'for 15 days',
    // Deliberately mirrors Pro's feature list -- the trial should
    // give full run of the app, not a capped preview, so an owner
    // can actually decide whether it's worth paying for based on
    // real use rather than an artificially limited sample.
    features: [
      'Everything in Pro, on us for 15 days',
      'Unlimited staff accounts',
      'Unlimited transaction history',
      '20 AI assistant credits / month',
      'Unlimited products',
    ],
    footnote: 'One-time trial — pick Basic or Pro once it ends to keep going.',
  ),
  _PlanInfo(
    id: 'basic',
    name: 'Basic',
    price: '₱290/mo',
    priceNote: 'or ₱2,900/yr',
    features: [
      '5 staff accounts',
      '90 days transaction history',
      '30 AI assistant credits / month',
      'Up to 30 products',
    ],
  ),
  _PlanInfo(
    id: 'pro',
    name: 'Pro',
    price: '₱690/mo',
    priceNote: 'or ₱6,900/yr',
    features: [
      'Unlimited staff accounts',
      'Unlimited transaction history',
      '90 AI assistant credits / month',
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
/// No real payment processing yet (Google Play Billing is a later,
/// separate build step) -- choosing a plan here just confirms intent
/// and tells the owner support will follow up, rather than silently
/// doing nothing or pretending to charge a card.
class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  void _choosePlan(BuildContext context, _PlanInfo plan) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('${plan.name} plan selected', style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
        content: Text(
          "Thanks! This doesn't charge anything yet -- we'll reach out shortly to help activate the ${plan.name} plan on your account.",
          style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreProvider>().store;
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
            for (final plan in _kPlans)
              _PlanCard(
                plan: plan,
                isCurrent: plan.id == currentPlanId,
                onChoose: () => _choosePlan(context, plan),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _PlanInfo plan;
  final bool isCurrent;
  final VoidCallback onChoose;

  const _PlanCard({required this.plan, required this.isCurrent, required this.onChoose});

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
              Text(plan.price, style: AppTextStyles.mono(size: 20, weight: FontWeight.w700, color: AppColors.ledAmber)),
              if (plan.priceNote != null) ...[
                const SizedBox(width: 8),
                Text(plan.priceNote!, style: AppTextStyles.body(size: 12, color: AppColors.textMuted)),
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
            // Free trial, not currently on it -- no "Choose" button;
            // it's a one-time onboarding period, not a plan you can
            // switch back to (see UpgradeScreen doc comment).
            Text(plan.footnote!, style: AppTextStyles.body(size: 12, color: AppColors.textMuted))
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onChoose,
                child: Text('Choose ${plan.name}', style: AppTextStyles.body(size: 13, weight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}
