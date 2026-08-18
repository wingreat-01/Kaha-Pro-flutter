import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/cart_provider.dart';
import '../state/ingredient_provider.dart';
import '../state/product_provider.dart';
import '../state/payment_method_provider.dart';
import '../models/payment_method.dart';
import '../state/recipe_provider.dart';
import '../state/transaction_provider.dart';
import '../theme/app_theme.dart';
import 'led_total.dart';

/// Result of the checkout flow. A queued sale still counts as
/// success from the cashier's point of view (cart cleared, stock
/// deducted) — completedSynced vs completedQueued just tells the
/// caller which message to show, not whether checkout worked.
enum CheckoutResult { cancelled, completedSynced, completedQueued }

/// Pass C checkout modal: cash payment entry + live change calculation,
/// reusing the LedTotal readout for both the amount due and the change
/// owed. Open via [CheckoutModal.show] from the "Checkout" button in
/// CartSidePanel / CartBottomBar.
class CheckoutModal extends StatefulWidget {
  final CartProvider cart;
  final String? cashierName;

  const CheckoutModal({super.key, required this.cart, this.cashierName});

  /// Opens the modal. Returns the outcome — cancelled, or completed
  /// (synced immediately or queued offline). If [onComplete] is
  /// provided, it's called once, after the dialog closes, only when
  /// checkout actually completed — use it for post-sale side effects
  /// like a confirmation snackbar, and check the result to word it
  /// correctly for a queued vs. synced sale.
  static Future<CheckoutResult> show(
    BuildContext context,
    CartProvider cart, {
    String? cashierName,
    void Function(CheckoutResult result)? onComplete,
  }) async {
    final result = await showDialog<CheckoutResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => CheckoutModal(cart: cart, cashierName: cashierName),
    );
    final resolved = result ?? CheckoutResult.cancelled;
    if (resolved != CheckoutResult.cancelled) {
      onComplete?.call(resolved);
    }
    return resolved;
  }

  @override
  State<CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends State<CheckoutModal> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;
  bool _submitting = false;

  // Selected on first build once PaymentMethodProvider is available —
  // defaults to whatever's first in sort_order (Cash, per the seeded
  // defaults) rather than nothing selected, so the common case needs
  // zero taps.
  PaymentMethod? _selectedMethod;
  bool _methodInitialized = false;

  // Only Cash shows the tendered-amount/change UI — every other method
  // (GCash, Maya, Bank Transfer, ...) is an exact-amount transfer, so
  // there's no "change" to calculate. Matched by name rather than a
  // separate flag on PaymentMethod, since Cash is a seeded default the
  // owner could rename — but "is this literally cash" is inherent to
  // the payment flow, not something the owner should be able to break
  // by renaming a row, so this checks the *original* seeded name.
  // If the owner deletes/renames the seeded "Cash" row entirely, this
  // falls back to non-cash behavior for everything, which is the safer
  // failure mode (no one accidentally skips collecting the right
  // amount).
  bool get _isCash => _selectedMethod?.name.trim().toLowerCase() == 'cash';

  double get _total => widget.cart.total;

  double? get _tendered {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  double get _change {
    final tendered = _tendered;
    if (tendered == null) return 0;
    final change = tendered - _total;
    return change > 0 ? change : 0;
  }

  bool get _canConfirm {
    if (_selectedMethod == null) return false;
    if (!_isCash) return true;
    final tendered = _tendered;
    return tendered != null && tendered >= _total;
  }

  void _setExact() {
    _controller.text = _total.toStringAsFixed(2);
    setState(() => _error = null);
  }

  void _addQuickAmount(double amount) {
    final current = _tendered ?? 0;
    _controller.text = (current + amount).toStringAsFixed(2);
    setState(() => _error = null);
  }

  void _setQuickTarget(double amount) {
    _controller.text = amount.toStringAsFixed(2);
    setState(() => _error = null);
  }

  double _ceilToMultiple(double value, double multiple) =>
      (value / multiple).ceil() * multiple;

  // Candidate cash amounts for the quick-amount chips.
  //
  // At or below ₱1000 (the largest common peso bill), chips are actual
  // cash values a customer would realistically hand over — tapping one
  // *adds* it to whatever's already entered, so a couple of taps can
  // stack bills together. An amount only shows if it alone could cover
  // the total (e.g. a ₱170 total hides ₱20/₱50/₱100 but keeps ₱200,
  // ₱500, ₱1000 — someone paying with two ₱100 bills, a ₱500 bill, or
  // only having a ₱1000 bill are all real cases, so nothing above the
  // due amount gets filtered out just because a smaller bill would also
  // clear it). These are the actual Philippine peso bill denominations.
  static const List<double> _billDenominations = [20, 50, 100, 200, 500, 1000];

  // Above ₱1000, no single bill covers the total, so there's nothing
  // sensible to "add". Instead offer nice round-up targets — next
  // ₱50, next ₱100, next ₱500 above the total — and tapping one *sets*
  // the tendered amount directly to that target (e.g. a ₱1043 total
  // offers ₱1050 / ₱1100 / ₱1500).
  List<double> get _quickRoundUpTargets {
    final targets = <double>{
      _ceilToMultiple(_total, 50),
      _ceilToMultiple(_total, 100),
      _ceilToMultiple(_total, 500),
    }.toList()
      ..sort();
    return targets;
  }

  bool get _useRoundUpTargets => _total > 1000;

  List<double> get _quickAmountOptions => _useRoundUpTargets
      ? _quickRoundUpTargets
      : _billDenominations.where((amount) => amount >= _total).toList();

  Future<void> _confirm() async {
    if (_selectedMethod == null) {
      setState(() => _error = 'Select a payment method.');
      return;
    }
    if (_isCash && !_canConfirm) {
      setState(() => _error = 'Amount tendered is less than the total due.');
      return;
    }
    if (_submitting) return; // guard double-tap while the request is in flight

    setState(() {
      _submitting = true;
      _error = null;
    });

    // Non-cash methods are exact-amount transfers — no tendered/change
    // to enter, so both collapse to the total itself / zero.
    final tendered = _isCash ? _tendered! : _total;
    final change = _isCash ? _change : 0.0;
    final soldItems = widget.cart.items; // snapshot before clearing

    try {
      final result = await context.read<TransactionProvider>().record(
            cartItems: soldItems,
            total: _total,
            cashTendered: tendered,
            change: change,
            cashierName: widget.cashierName,
            paymentMethodId: _selectedMethod!.id,
            paymentMethodName: _selectedMethod!.name,
          );

      if (!mounted) return;

      // Deduct stock once the sale is at least recorded (synced or
      // queued) — using the same pre-clear snapshot of cart lines the
      // transaction was recorded from, keeping stock and the
      // transaction log in sync with the same sale.
      //
      // Awaited (not fire-and-forget) so this try/catch actually
      // catches a failure here instead of letting it become an
      // unhandled Future rejection. Expected to fail/roll-back when
      // this sale itself just got queued offline — that's fine, since
      // TransactionProvider.syncPending() retries the deduction (via
      // deductStockForLineItems) once the sale actually syncs. See
      // login_screen.dart for that wiring.
      try {
        await context.read<ProductProvider>().deductStockForSale(soldItems);
      } catch (_) {
        // Swallowed deliberately — see note above.
      }

      // Recipe-based ingredient deduction (Step 5) — same
      // fire-and-catch reasoning as the product stock deduction just
      // above: if this sale is queued offline, there's no recipe data
      // to look up reliably yet anyway, and TransactionProvider.
      // syncPending() is the real retry path once it syncs. Computing
      // the deductions and writing them are two separate awaited
      // calls (not combined) so a failure in one doesn't obscure
      // whether the lookup or the write actually failed, though both
      // paths are swallowed here identically either way.
      try {
        final deductions =
            await context.read<RecipeProvider>().computeDeductionsForSale(soldItems);
        if (deductions.isNotEmpty) {
          await context.read<IngredientProvider>().deductStockForSale(deductions);
        }
      } catch (_) {
        // Swallowed deliberately — negative-stock policy is allow, no
        // warning, and a lookup/write failure here shouldn't block or
        // taint an already-recorded sale.
      }

      widget.cart.clear();
      Navigator.of(context).pop(
        result.isPending ? CheckoutResult.completedQueued : CheckoutResult.completedSynced,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not save the sale — check your connection and try again.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final methods = context.watch<PaymentMethodProvider>().activeMethods;

    // Default to the first active method (Cash, per the seeded
    // defaults/sort_order) the first time methods are available —
    // done in build() rather than initState() since the provider's
    // data may not be loaded yet when this modal first opens.
    if (!_methodInitialized && methods.isNotEmpty) {
      _selectedMethod = methods.first;
      _methodInitialized = true;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.slate,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slateBorder, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'CHECKOUT',
                      style: AppTextStyles.mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(CheckoutResult.cancelled),
                      icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                      splashRadius: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LedTotal(amount: _total, label: 'TOTAL DUE'),
                const SizedBox(height: 18),
                Text(
                  'PAYMENT METHOD',
                  style: AppTextStyles.mono(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                if (methods.isEmpty)
                  Text(
                    'No payment methods set up — add one in Settings.',
                    style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final method in methods)
                        _MethodChip(
                          label: method.name,
                          selected: _selectedMethod?.id == method.id,
                          onTap: () => setState(() {
                            _selectedMethod = method;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 18),
                if (_isCash) ...[
                  Text(
                    'CASH TENDERED',
                    style: AppTextStyles.mono(
                      size: 11,
                      weight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: AppTextStyles.mono(size: 22, weight: FontWeight.w700, color: AppColors.ledAmber),
                    decoration: InputDecoration(
                      prefixText: '₱ ',
                      prefixStyle: AppTextStyles.mono(size: 22, weight: FontWeight.w700, color: AppColors.ledAmber),
                      hintText: '0.00',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _confirm(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _QuickChip(label: 'Exact', onTap: _setExact),
                      for (final amount in _quickAmountOptions)
                        _QuickChip(
                          label: _useRoundUpTargets
                              ? '₱${amount.toStringAsFixed(0)}'
                              : '+₱${amount.toStringAsFixed(0)}',
                          onTap: () => _useRoundUpTargets
                              ? _setQuickTarget(amount)
                              : _addQuickAmount(amount),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LedTotal(
                    amount: _change,
                    label: 'CHANGE',
                    fontSize: 26,
                    color: AppColors.tillGreen,
                  ),
                ] else if (_selectedMethod != null)
                  Text(
                    'Confirming ₱${_total.toStringAsFixed(2)} via ${_selectedMethod!.name}. No change due.',
                    style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed, weight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_submitting || methods.isEmpty) ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.tillGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm payment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.ledAmber.withOpacity(0.15) : AppColors.slateField,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.ledAmber : AppColors.slateBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.mono(
            size: 12,
            weight: FontWeight.w700,
            color: selected ? AppColors.ledAmber : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.slateField,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.slateBorder, width: 1),
        ),
        child: Text(
          label,
          style: AppTextStyles.mono(size: 12, weight: FontWeight.w600, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
