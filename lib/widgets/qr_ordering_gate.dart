import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/upgrade_screen.dart';
import '../state/store_provider.dart';
import '../theme/app_theme.dart';

/// Plan gate for QR Ordering (Basic and Pro only; the free trial
/// mirrors Pro). Wrap any QR Ordering screen in this: it shows [child]
/// when the store's plan includes the feature, otherwise a locked
/// screen with an upgrade button.
///
///   QrOrderingGate(child: IncomingOrdersPanel(...))           // inside the shell
///   QrOrderingGate(fullScreen: true, child: TablesPanel())    // pushed route
///
/// Set [fullScreen] for pushed routes so the locked view gets an
/// AppBar with a back button; leave it off when the gate sits inside a
/// screen that already provides its own chrome.
///
/// This is a UX gate only -- the server (RLS / order-submit function)
/// must enforce the same rule, since the customer's QR order page never
/// goes through the app.
class QrOrderingGate extends StatelessWidget {
  final Widget child;
  final bool fullScreen;

  const QrOrderingGate({
    super.key,
    required this.child,
    this.fullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final allowed = context.watch<StoreProvider>().canUseQrOrdering;
    if (allowed) return child;

    final locked = const _LockedView();
    if (!fullScreen) return locked;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('QR Ordering',
            style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      body: locked,
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView();

  @override
  Widget build(BuildContext context) {
    final expired = context.watch<StoreProvider>().isExpired;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.slateField,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.slateBorder, width: 1),
                ),
                child: Icon(Icons.lock_outline,
                    size: 28, color: AppColors.ledAmber),
              ),
              const SizedBox(height: 18),
              Text(
                'QR Ordering is a Basic & Pro feature',
                textAlign: TextAlign.center,
                style: AppTextStyles.mono(size: 15, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                expired
                    ? 'Your trial has ended. Pick a plan to let customers scan, order and pay from their table.'
                    : 'Upgrade to Basic or Pro to let customers scan a table QR, order from your menu and pay from their phone.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ledAmber,
                  foregroundColor: AppColors.charcoal,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Text('See plans'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
