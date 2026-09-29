import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/cart_item.dart';
import '../models/incoming_order.dart';
import '../models/payment_method.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/transaction.dart';
import '../state/currency_provider.dart';
import '../state/incoming_order_provider.dart';
import '../state/ingredient_provider.dart';
import '../state/payment_method_provider.dart';
import '../state/product_provider.dart';
import '../state/recipe_provider.dart';
import '../state/transaction_provider.dart';
import '../widgets/bounded_content.dart';

/// Cashier-facing queue of orders customers sent from a table's QR code.
/// HomeShell provides the app bar, so this is body-only (like
/// TransactionsPanel). Pull down to refresh; new orders also arrive
/// live via IncomingOrderProvider's realtime subscription.
///
/// Four tabs follow the order through the shop:
///   New        -> Accept (kitchen starts) or Reject
///   Preparing  -> Mark ready
///   Ready      -> Complete (rings the order up as a real sale)
///   Done       -> completed / rejected history
/// The customer's phone shows the same status live.
class IncomingOrdersPanel extends StatelessWidget {
  final String? cashierName;
  const IncomingOrdersPanel({super.key, this.cashierName});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IncomingOrderProvider>();

    if (provider.isLoading && provider.orders.isEmpty) {
      return const BoundedContent(child: Center(child: CircularProgressIndicator()));
    }
    if (provider.loadError != null && provider.orders.isEmpty) {
      return BoundedContent(
        child: RefreshIndicator(
          onRefresh: () => context.read<IncomingOrderProvider>().load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load orders. Pull down to try again.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(size: 14, color: AppColors.ledgerRed),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pending = provider.pending;
    final preparing = provider.preparing;
    final ready = provider.ready;
    final done = provider.done;

    String label(String name, int n) => n > 0 ? '$name ($n)' : name;

    return BoundedContent(
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            TabBar(
              labelColor: AppColors.ledAmber,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.ledAmber,
              dividerColor: AppColors.slateBorder,
              labelStyle: AppTextStyles.body(size: 12.5, weight: FontWeight.w700),
              unselectedLabelStyle: AppTextStyles.body(size: 12.5, weight: FontWeight.w600),
              tabs: [
                Tab(text: label('New', pending.length)),
                Tab(text: label('Preparing', preparing.length)),
                Tab(text: label('Ready', ready.length)),
                const Tab(text: 'Done'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OrderList(
                    orders: pending,
                    cashierName: cashierName,
                    empty: 'No new orders. Orders from table QR codes appear here automatically.',
                  ),
                  _OrderList(
                    orders: preparing,
                    cashierName: cashierName,
                    empty: 'Nothing is being prepared right now.',
                  ),
                  _OrderList(
                    orders: ready,
                    cashierName: cashierName,
                    empty: 'No orders waiting for pickup.',
                  ),
                  _OrderList(
                    orders: done,
                    cashierName: cashierName,
                    empty: 'Completed and rejected orders show up here.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<IncomingOrder> orders;
  final String empty;
  final String? cashierName;
  const _OrderList({required this.orders, required this.empty, required this.cashierName});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<IncomingOrderProvider>().load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  empty,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
                ),
              ),
            ),
          for (final order in orders)
            _OrderCard(key: ValueKey(order.id), order: order, cashierName: cashierName),
        ],
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final IncomingOrder order;
  final String? cashierName;
  const _OrderCard({super.key, required this.order, required this.cashierName});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _busy = false;

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.body(size: 13, color: Colors.white, weight: FontWeight.w600),
        ),
        backgroundColor: error ? AppColors.ledgerRed : const Color(0xFF2E7D32),
        duration: Duration(seconds: error ? 7 : 3),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('Could not update this order. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String confirmLabel, {bool danger = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text(title, style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
        content: Text(message, style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: AppTextStyles.body(
                size: 13,
                weight: FontWeight.w700,
                color: danger ? AppColors.ledgerRed : AppColors.ledAmber,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _info(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text(title, style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
        content: Text(message, style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('OK', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber)),
          ),
        ],
      ),
    );
  }

  Future<void> _accept() async {
    final order = widget.order;
    final provider = context.read<IncomingOrderProvider>();
    if (order.isOnline && !order.isPaid) {
      final ok = await _confirm(
        'Payment not confirmed yet',
        'This customer says they paid online (ref ${order.paymentReference ?? '-'}), but you haven\'t marked the payment as received. Accept the order anyway?',
        'Accept anyway',
      );
      if (!ok) return;
    }
    await _run(() => provider.accept(order));
  }

  Future<void> _reject() async {
    final order = widget.order;
    final provider = context.read<IncomingOrderProvider>();
    final ok = await _confirm(
      'Reject this order?',
      order.isOnline && order.paymentStatus != 'unpaid'
          ? 'The customer reported an online payment. If you already received it, refund them outside the app. Their phone will show that the order was not accepted.'
          : 'Their phone will show that the order was not accepted.',
      'Reject',
      danger: true,
    );
    if (!ok) return;
    await _run(() => provider.reject(order));
  }

  Future<void> _markReady() async {
    final order = widget.order;
    final provider = context.read<IncomingOrderProvider>();
    await _run(() => provider.markReady(order));
  }

  Future<void> _markPaid() async {
    final order = widget.order;
    final provider = context.read<IncomingOrderProvider>();
    await _run(() => provider.markPaid(order));
  }

  Product? _findProduct(List<Product> catalog, String? id) {
    if (id == null) return null;
    for (final p in catalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Rings the order up as a real sale (same record_transaction path the
  /// Register uses, so numbering, reports and stock all stay correct),
  /// then marks the order completed.
  Future<void> _complete() async {
    final order = widget.order;
    final incoming = context.read<IncomingOrderProvider>();

    if (order.isOnline && !order.isPaid) {
      await _info(
        'Confirm the payment first',
        'This is an online order and its payment has not been marked as received. Check your e-wallet, tap "Payment received", then complete the order.',
      );
      return;
    }

    final txns = context.read<TransactionProvider>();
    final products = context.read<ProductProvider>();
    final recipes = context.read<RecipeProvider>();
    final ingredients = context.read<IngredientProvider>();
    final methods = context.read<PaymentMethodProvider>().activeMethods;

    String? saleId;

    if (incoming.hasRecordedSale(order.id)) {
      // An earlier attempt already saved the sale but failed to flip the
      // order's status. Only finish the status update -- never charge twice.
      saleId = incoming.recordedSaleId(order.id);
    } else {
      if (methods.isEmpty) {
        _snack('Add a payment method in Settings first.', error: true);
        return;
      }
      final choice = await showDialog<_PayChoice>(
        context: context,
        builder: (_) => _CompleteDialog(order: order, methods: methods),
      );
      if (choice == null || !mounted) return;

      setState(() => _busy = true);
      try {
        final catalog = products.products;
        final lines = <TransactionLineItem>[];
        final cartItems = <CartItem>[];
        for (final item in order.items) {
          final product = _findProduct(catalog, item.productId);
          if (product == null) {
            throw StateError('"${item.name}" is no longer in your menu, so this order cannot be rung up.');
          }
          ProductVariant? variant;
          if (item.variantId != null) {
            for (final v in product.variants) {
              if (v.id == item.variantId) variant = v;
            }
          }
          lines.add(TransactionLineItem(
            productId: product.id,
            name: item.saleName,
            price: item.price, // price the customer saw when ordering
            quantity: item.quantity,
            category: product.category,
            variantId: variant?.id,
            variantName: item.variantName,
          ));
          cartItems.add(CartItem(product: product, selectedVariant: variant, quantity: item.quantity));
        }

        final result = await txns.record(
          lineItems: lines,
          total: order.total,
          cashTendered: choice.tendered,
          change: choice.change,
          cashierName: widget.cashierName,
          paymentMethodId: choice.method.id,
          paymentMethodName: choice.method.name,
        );
        saleId = result.id;
        incoming.rememberSale(order.id, saleId);

        // Same stock handling as CheckoutModal: failures here never undo
        // an already-recorded sale.
        try {
          await products.deductStockForLineItems(lines);
        } catch (_) {}
        try {
          final deductions = await recipes.computeDeductionsForSale(cartItems);
          if (deductions.isNotEmpty) {
            await ingredients.deductStockForSale(
              deductions,
              reference: result.isPending ? null : result.transactionNumber,
              staffName: widget.cashierName,
            );
          }
        } catch (_) {}
      } catch (e) {
        _snack(e is StateError ? e.message : 'Could not record the sale: $e', error: true);
        if (mounted) setState(() => _busy = false);
        return;
      }
    }

    if (mounted) setState(() => _busy = true);
    try {
      await incoming.complete(order, transactionId: saleId);
      _snack('Order ${order.numberLabel} completed and recorded as a sale.');
    } catch (e) {
      _snack(
        'The sale was recorded, but the order could not be marked completed. Tap Complete again to finish. It will not charge twice.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final status = order.status;
    final isPending = status == 'pending';
    final isPreparing = status == 'preparing';
    final isReady = status == 'ready';
    final isCompleted = status == 'completed';
    final rejected = status == 'rejected';
    final active = isPending || isPreparing || isReady;
    final name = (order.customerName == null || order.customerName!.isEmpty) ? null : order.customerName;

    return Opacity(
      opacity: rejected ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.slate,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPending || isReady ? AppColors.ledAmber : AppColors.slateBorder,
            width: isPending || isReady ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  order.numberLabel,
                  style: AppTextStyles.mono(size: 20, weight: FontWeight.w800, color: AppColors.ledAmber),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name == null ? order.tableLabel : '${order.tableLabel} · $name',
                    style: AppTextStyles.body(size: 15, weight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_ago(order.createdAt), style: AppTextStyles.mono(size: 10.5, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}× ${item.displayName}',
                        style: AppTextStyles.body(size: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(context.money(item.lineTotal), style: AppTextStyles.mono(size: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            const Divider(height: 22),
            Row(
              children: [
                _PaymentChip(order: order),
                const Spacer(),
                Text(context.money(order.total), style: AppTextStyles.mono(size: 16, weight: FontWeight.w700, color: AppColors.ledAmber)),
              ],
            ),
            if (order.isOnline && order.paymentReference != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Reference: ${order.paymentReference}',
                style: AppTextStyles.mono(size: 12.5, color: AppColors.textSecondary),
              ),
            ],
            if (isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Completed',
                  style: AppTextStyles.body(size: 12, weight: FontWeight.w600, color: AppColors.tillGreen),
                ),
              ),
            if (rejected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Rejected',
                  style: AppTextStyles.body(size: 12, weight: FontWeight.w600, color: AppColors.ledgerRed),
                ),
              ),
            if (active) ...[
              const SizedBox(height: 12),
              if (_busy)
                const Center(
                  child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isPending)
                      OutlinedButton(
                        onPressed: _reject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.ledgerRed,
                          side: BorderSide(color: AppColors.ledgerRed),
                        ),
                        child: const Text('Reject'),
                      ),
                    if (!order.isPaid)
                      OutlinedButton(
                        onPressed: _markPaid,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.tillGreen,
                          side: BorderSide(color: AppColors.tillGreen),
                        ),
                        child: Text(order.isOnline ? 'Payment received' : 'Paid at counter'),
                      ),
                    if (isPending)
                      FilledButton(
                        onPressed: _accept,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ledAmber,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Accept'),
                      ),
                    if (isPreparing)
                      FilledButton(
                        onPressed: _markReady,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ledAmber,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Mark ready'),
                      ),
                    if (isReady)
                      FilledButton(
                        onPressed: _complete,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.tillGreen,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Complete'),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final IncomingOrder order;
  const _PaymentChip({required this.order});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (order.isPaid) {
      label = order.isOnline ? 'PAID ONLINE' : 'PAID';
      color = AppColors.tillGreen;
    } else if (order.isOnline) {
      label = 'ONLINE · VERIFY PAYMENT';
      color = AppColors.ledAmber;
    } else {
      label = 'PAY AT COUNTER';
      color = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.6), width: 1),
      ),
      child: Text(label, style: AppTextStyles.mono(size: 10, weight: FontWeight.w700, color: color, letterSpacing: 0.5)),
    );
  }
}

/// What the cashier picked in the Complete dialog.
class _PayChoice {
  final PaymentMethod method;
  final double tendered;
  final double change;
  const _PayChoice({required this.method, required this.tendered, required this.change});
}

/// Asks how the order was paid so the sale is recorded with the right
/// payment method (and cash tendered / change for cash).
class _CompleteDialog extends StatefulWidget {
  final IncomingOrder order;
  final List<PaymentMethod> methods;
  const _CompleteDialog({required this.order, required this.methods});

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  late PaymentMethod _method;
  late final TextEditingController _tenderCtrl;
  String? _error;

  bool _isCash(PaymentMethod m) => m.name.trim().toLowerCase() == 'cash';

  @override
  void initState() {
    super.initState();
    final methods = widget.methods;
    PaymentMethod? pick;
    // Online orders were paid by e-wallet/bank, counter orders usually by cash.
    for (final m in methods) {
      if (widget.order.isOnline ? !_isCash(m) : _isCash(m)) {
        pick = m;
        break;
      }
    }
    _method = pick ?? methods.first;
    _tenderCtrl = TextEditingController(text: widget.order.total.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _tenderCtrl.dispose();
    super.dispose();
  }

  double? get _tendered => double.tryParse(_tenderCtrl.text.trim());

  void _confirm() {
    final total = widget.order.total;
    if (_isCash(_method)) {
      final tendered = _tendered;
      if (tendered == null || tendered + 0.001 < total) {
        setState(() => _error = 'Amount tendered is less than the total.');
        return;
      }
      Navigator.of(context).pop(_PayChoice(method: _method, tendered: tendered, change: tendered - total));
    } else {
      Navigator.of(context).pop(_PayChoice(method: _method, tendered: total, change: 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final cash = _isCash(_method);
    final tendered = _tendered;
    final change = (cash && tendered != null) ? tendered - order.total : 0.0;

    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text('Complete ${order.numberLabel}', style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total ${context.money(order.total)}',
              style: AppTextStyles.mono(size: 18, weight: FontWeight.w700, color: AppColors.ledAmber),
            ),
            const SizedBox(height: 4),
            Text(
              'This records the order as a sale.',
              style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Text('Paid with', style: AppTextStyles.body(size: 12, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in widget.methods)
                  ChoiceChip(
                    label: Text(m.name),
                    selected: m.id == _method.id,
                    selectedColor: AppColors.ledAmber,
                    labelStyle: AppTextStyles.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: m.id == _method.id ? Colors.black : AppColors.textPrimary,
                    ),
                    onSelected: (_) => setState(() {
                      _method = m;
                      _error = null;
                    }),
                  ),
              ],
            ),
            if (cash) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _tenderCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTextStyles.mono(size: 15),
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(labelText: 'Amount tendered'),
              ),
              const SizedBox(height: 8),
              Text(
                'Change: ${context.money(change < 0 ? 0 : change)}',
                style: AppTextStyles.mono(size: 13, color: AppColors.textSecondary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _confirm,
          child: Text('Record sale', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber)),
        ),
      ],
    );
  }
}
