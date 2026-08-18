import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/pending_sale.dart';
import '../models/sales_report.dart';
import '../models/transaction.dart';

/// Transaction log for the Register screen. Backed by Supabase
/// (`transactions` + `transaction_line_items`, written atomically via
/// the `record_transaction` RPC), with a local offline queue: a sale
/// that can't reach Supabase at checkout time is persisted to disk
/// (SharedPreferences) instead of being lost, shown in the
/// Transactions tab as PENDING, and retried automatically the next
/// time this provider successfully talks to Supabase.
///
/// Wrap the app with ChangeNotifierProvider<TransactionProvider> in
/// main.dart to use this.
class TransactionProvider extends ChangeNotifier {
  static const _pendingStorageKey = 'kahapro_pending_sales';

  final List<Transaction> _transactions = [];
  final List<PendingSale> _pendingQueue = [];
  final _client = Supabase.instance.client;

  /// Newest first, for the Transactions tab list.
  List<Transaction> get transactions => List.unmodifiable(_transactions.reversed);

  bool get isEmpty => _transactions.isEmpty;

  /// Sales queued locally, not yet synced to Supabase. Surface this
  /// somewhere in the UI (a badge on the Transactions icon, a banner)
  /// so a cashier isn't surprised later that some "completed" sales
  /// were actually still pending.
  int get pendingCount => _pendingQueue.length;

  /// All transactions grouped by calendar day, newest day first (each
  /// day's own transactions are also newest first, since `transactions`
  /// already is — Dart's Map preserves insertion order, so no extra
  /// sort is needed here).
  List<DaySummary> get dailySummaries {
    final Map<DateTime, List<Transaction>> grouped = {};
    for (final txn in transactions) {
      final day = DateTime(txn.timestamp.year, txn.timestamp.month, txn.timestamp.day);
      grouped.putIfAbsent(day, () => []).add(txn);
    }
    return grouped.entries.map((e) => DaySummary(day: e.key, transactions: e.value)).toList();
  }

  /// Builds a SalesReport for the given date range — the real data
  /// source behind ReportsScreen's reportBuilder callback, replacing
  /// its built-in mock generator. Everything's computed from the
  /// already-in-memory _transactions list (same source dailySummaries
  /// uses above), so this is just aggregation, no extra Supabase
  /// round-trip. Includes still-pending (unsynced) sales — a queued
  /// sale is a real completed cash sale as far as the owner's numbers
  /// are concerned, it just hasn't reached Supabase yet.
  ///
  /// [range] is treated as inclusive on both ends — pass
  /// DateTimeRange(start: <day 00:00:00>, end: <day 23:59:59>) for a
  /// single-day report, which is what ReportsScreen's presets already
  /// build.
  SalesReport reportFor(DateTimeRange range) {
    final inRange = _transactions
        .where((t) => !t.timestamp.isBefore(range.start) && !t.timestamp.isAfter(range.end))
        .toList();

    double totalRevenue = 0;
    int itemsSold = 0;
    final productTotals = <String, _ProductAgg>{};
    final cashierTotals = <String, _CashierAgg>{};

    for (final txn in inRange) {
      totalRevenue += txn.total;

      // cashierName is null on older rows recorded before it was
      // captured — group those under a visible "Unknown" bucket
      // rather than silently dropping them from the breakdown.
      final cashierKey = txn.cashierName ?? 'Unknown';
      final cashierAgg = cashierTotals.putIfAbsent(cashierKey, () => _CashierAgg());
      cashierAgg.transactionCount += 1;
      cashierAgg.revenue += txn.total;

      for (final item in txn.items) {
        itemsSold += item.quantity;
        // Keyed on (productId, variantId) so "Coffee (Large)" and
        // "Coffee (Medium)" tally separately, matching how the cart
        // itself keys lines — same reasoning as CartProvider.
        final key = '${item.productId}::${item.variantId ?? ''}';
        final productAgg = productTotals.putIfAbsent(
          key,
          () => _ProductAgg(productId: item.productId, variantId: item.variantId, displayName: item.name),
        );
        productAgg.quantitySold += item.quantity;
        productAgg.revenue += item.lineTotal;
      }
    }

    final productBreakdown = productTotals.values
        .map((a) => ProductSalesLine(
              productId: a.productId,
              variantId: a.variantId,
              displayName: a.displayName,
              quantitySold: a.quantitySold,
              revenue: a.revenue,
            ))
        .toList();

    final cashierBreakdown = cashierTotals.entries
        .map((e) => CashierSalesLine(
              cashierName: e.key,
              transactionCount: e.value.transactionCount,
              revenue: e.value.revenue,
            ))
        .toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return SalesReport(
      rangeStart: range.start,
      rangeEnd: range.end,
      // All sales here are cash, so cash actually taken in equals
      // revenue — kept as a separate field on SalesReport (rather than
      // just reusing totalRevenue in the UI) so a future non-cash
      // tender type only needs a change here, not in ReportsScreen.
      totalRevenue: totalRevenue,
      cashIn: totalRevenue,
      transactionCount: inRange.length,
      itemsSold: itemsSold,
      productBreakdown: productBreakdown,
      cashierBreakdown: cashierBreakdown,
    );
  }

  Future<void> _loadPendingFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingStorageKey);
    if (raw == null || raw.isEmpty) return;
    _pendingQueue
      ..clear()
      ..addAll(PendingSale.decodeList(raw));
  }

  Future<void> _savePendingToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingStorageKey, PendingSale.encodeList(_pendingQueue));
  }

  /// Fetch-once-on-login, same pattern as ProductProvider.loadFromSupabase().
  /// Also restores any sales queued locally from a previous session
  /// (e.g. the app was closed while still offline) so they still show
  /// as PENDING in the Transactions tab. Does NOT sync them itself —
  /// call syncPending() afterward (with a deductStock callback wired
  /// to ProductProvider) once this resolves, so stock deduction can
  /// run for anything that syncs. See login_screen.dart.
  Future<void> loadFromSupabase() async {
    await _loadPendingFromDisk();

    final rows = await _client
        .from('transactions')
        .select('*, transaction_line_items(*), payment_methods(name)')
        .order('created_at');

    _transactions
      ..clear()
      ..addAll(rows.map<Transaction>((row) => _fromRow(row as Map<String, dynamic>)));

    // Re-show any still-unsynced local sales as PENDING placeholders —
    // otherwise they'd vanish from the Transactions tab the moment the
    // server fetch above overwrote the in-memory list.
    for (final pending in _pendingQueue) {
      _transactions.add(_placeholderFor(pending));
    }
    notifyListeners();
  }

  Transaction _placeholderFor(PendingSale pending) {
    return Transaction(
      id: null,
      localId: pending.localId,
      cashierName: pending.cashierName,
      transactionNumber: 'PENDING',
      timestamp: pending.queuedAt,
      items: pending.items,
      total: pending.total,
      cashTendered: pending.cashTendered,
      change: pending.change,
      paymentMethodId: pending.paymentMethodId,
      paymentMethodName: pending.paymentMethodName,
    );
  }

  List<Map<String, dynamic>> _itemsJson(List<TransactionLineItem> items) {
    return items
        .map((li) => {
              'product_id': li.productId,
              'product_name': li.name,
              'category': li.category,
              'unit_price': li.price,
              'quantity': li.quantity,
              'line_total': li.lineTotal,
              'variant_id': li.variantId,
              'variant_name': li.variantName,
            })
        .toList();
  }

  /// Records a completed sale. Call this with the cart's items BEFORE
  /// clearing the cart, so quantities are still intact.
  ///
  /// Async — this hits Supabase (record_transaction RPC). If that
  /// fails for what looks like a connectivity reason, the sale is
  /// queued locally instead of being lost — the caller still gets
  /// back a Transaction (check `.isPending` to tell which happened),
  /// so checkout can still complete and the cart can still clear. If
  /// it fails for a real reason (bad data, RLS denial — something a
  /// retry won't fix), this rethrows and the caller must NOT proceed
  /// as if the sale succeeded.
  Future<Transaction> record({
    required List<CartItem> cartItems,
    required double total,
    required double cashTendered,
    required double change,
    String? cashierName,
    String? paymentMethodId,
    String? paymentMethodName,
  }) async {
    final lineItems = cartItems.map(TransactionLineItem.fromCartItem).toList();

    try {
      final row = await _client.rpc('record_transaction', params: {
        'p_total': total,
        'p_cash_tendered': cashTendered,
        'p_change_amount': change,
        'p_cashier_name': cashierName,
        'p_items': _itemsJson(lineItems),
        'p_payment_method_id': paymentMethodId,
      }).single();

      final transaction = Transaction(
        id: row['id'] as String,
        cashierName: row['cashier_name'] as String?,
        transactionNumber: '#${(row['transaction_number'] as int).toString().padLeft(5, '0')}',
        timestamp: DateTime.parse(row['created_at'] as String).toLocal(),
        items: lineItems,
        total: total,
        cashTendered: cashTendered,
        change: change,
        paymentMethodId: row['payment_method_id'] as String?,
        // record_transaction's RETURNS transactions doesn't include the
        // joined method name (that's only fetched via loadFromSupabase's
        // select) — carry the name the caller already had (from
        // PaymentMethodProvider) rather than leaving it null for the
        // rest of this session.
        paymentMethodName: paymentMethodName,
      );

      _transactions.add(transaction);
      notifyListeners();
      return transaction;
    } catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        return _queueOffline(
          lineItems: lineItems,
          total: total,
          cashTendered: cashTendered,
          change: change,
          cashierName: cashierName,
          paymentMethodId: paymentMethodId,
          paymentMethodName: paymentMethodName,
        );
      }
      rethrow;
    }
  }

  /// Distinguishes "couldn't reach the server at all" (safe to queue
  /// and silently retry) from "the server responded and said no"
  /// (queuing would just fail the same way forever — a bad product id,
  /// an RLS denial, etc. needs to surface immediately, not disappear
  /// into a queue that quietly never syncs).
  ///
  /// Deliberately no dart:io SocketException check — this app also
  /// targets Flutter web (flutter run -d web-server), where dart:io
  /// isn't available at all. PostgrestException/AuthException mean
  /// the server responded, so those are treated as real failures;
  /// everything else (fetch aborted, DNS failure, timeout) is treated
  /// as connectivity-related, since queuing is the safer default when
  /// unsure — losing a completed sale is worse than retrying one that
  /// turns out to fail again later.
  bool _isLikelyNetworkFailure(Object e) {
    if (e is PostgrestException) return false;
    if (e is AuthException) return false;
    return true;
  }

  Transaction _queueOffline({
    required List<TransactionLineItem> lineItems,
    required double total,
    required double cashTendered,
    required double change,
    String? cashierName,
    String? paymentMethodId,
    String? paymentMethodName,
  }) {
    final pending = PendingSale(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      total: total,
      cashTendered: cashTendered,
      change: change,
      cashierName: cashierName,
      items: lineItems,
      queuedAt: DateTime.now(),
      paymentMethodId: paymentMethodId,
      paymentMethodName: paymentMethodName,
    );
    _pendingQueue.add(pending);
    unawaited(_savePendingToDisk());

    final placeholder = _placeholderFor(pending);
    _transactions.add(placeholder);
    notifyListeners();
    return placeholder;
  }

  /// Retries every queued sale against Supabase. Call this after
  /// loadFromSupabase() resolves — pass [deductStock] wired to
  /// ProductProvider.deductStockForLineItems so stock actually gets
  /// deducted for a sale that only just now managed to sync (the
  /// immediate checkout-time deduction attempt fails/rolls back while
  /// offline, by design — this is where a queued sale's stock
  /// deduction actually lands, once connectivity returns).
  Future<void> syncPending({
    Future<void> Function(List<TransactionLineItem> items)? deductStock,
  }) async {
    if (_pendingQueue.isEmpty) return;

    final stillPending = <PendingSale>[];
    for (final pending in List<PendingSale>.from(_pendingQueue)) {
      try {
        final row = await _client.rpc('record_transaction', params: {
          'p_total': pending.total,
          'p_cash_tendered': pending.cashTendered,
          'p_change_amount': pending.change,
          'p_cashier_name': pending.cashierName,
          'p_items': _itemsJson(pending.items),
          'p_payment_method_id': pending.paymentMethodId,
        }).single();

        final synced = Transaction(
          id: row['id'] as String,
          cashierName: row['cashier_name'] as String?,
          transactionNumber: '#${(row['transaction_number'] as int).toString().padLeft(5, '0')}',
          timestamp: DateTime.parse(row['created_at'] as String).toLocal(),
          items: pending.items,
          total: pending.total,
          cashTendered: pending.cashTendered,
          change: pending.change,
          paymentMethodId: row['payment_method_id'] as String?,
          paymentMethodName: pending.paymentMethodName,
        );

        // Swap the PENDING placeholder for the now-real synced row.
        _transactions.removeWhere((t) => t.localId == pending.localId);
        _transactions.add(synced);

        if (deductStock != null) {
          try {
            await deductStock(pending.items);
          } catch (_) {
            // The sale itself is synced and stays synced even if this
            // fails — better to keep a recorded sale with possibly
            // stale stock than to undo a real transaction over a
            // stock-side hiccup. No automatic retry for just the
            // stock side yet; stock could drift here until the next
            // manual stock recount/adjustment.
          }
        }
      } catch (e) {
        // Still unreachable, or a genuine rejection surfacing only
        // now (e.g. a product referenced in the sale was deleted in
        // the meantime) — leave it queued. Discarding a permanently-
        // failing entry is now a deliberate, manual action instead
        // (see discardPending() below) rather than automatic.
        stillPending.add(pending);
      }
    }

    _pendingQueue
      ..clear()
      ..addAll(stillPending);
    await _savePendingToDisk();
    notifyListeners();
  }

  /// Permanently drops a queued sale that will never sync (e.g. its
  /// product was deleted before it could sync) or that the cashier
  /// decides to abandon. Unlike syncPending()'s automatic retry, this
  /// is a deliberate, irreversible action — the sale's PENDING row
  /// disappears from the Transactions tab and it's no longer retried.
  /// There's nothing to clean up server-side: a queued sale that never
  /// synced was never written to Supabase in the first place, so no
  /// stock was ever deducted for it either.
  Future<void> discardPending(String localId) async {
    final stillQueued = _pendingQueue.any((p) => p.localId == localId);
    if (!stillQueued) return;

    _pendingQueue.removeWhere((p) => p.localId == localId);
    _transactions.removeWhere((t) => t.localId == localId);
    await _savePendingToDisk();
    notifyListeners();
  }

  Transaction _fromRow(Map<String, dynamic> row) {
    final lineRows = (row['transaction_line_items'] as List).cast<Map<String, dynamic>>();
    return Transaction(
      id: row['id'] as String,
      cashierName: row['cashier_name'] as String?,
      transactionNumber: '#${(row['transaction_number'] as int).toString().padLeft(5, '0')}',
      timestamp: DateTime.parse(row['created_at'] as String).toLocal(),
      items: lineRows
          .map((li) => TransactionLineItem(
                // product_id is nullable on the table (a later product
                // delete shouldn't orphan the historical line item) —
                // default to '' rather than widen this field's type.
                productId: li['product_id'] as String? ?? '',
                name: li['product_name'] as String,
                price: (li['unit_price'] as num).toDouble(),
                quantity: li['quantity'] as int,
                category: li['category'] as String,
                variantId: li['variant_id'] as String?,
                variantName: li['variant_name'] as String?,
              ))
          .toList(),
      total: (row['total'] as num).toDouble(),
      cashTendered: (row['cash_tendered'] as num).toDouble(),
      change: (row['change_amount'] as num).toDouble(),
      paymentMethodId: row['payment_method_id'] as String?,
      // Null on rows where the method was later deleted (FK is
      // nullable, no ON DELETE restriction assumed) or on rows
      // recorded before this feature existed.
      paymentMethodName: (row['payment_methods'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}

/// Mutable running totals used only inside reportFor() while grouping
/// — converted to the immutable ProductSalesLine/CashierSalesLine
/// models before being returned, so nothing mutable ever leaves this
/// file.
class _ProductAgg {
  final String productId;
  final String? variantId;
  final String displayName;
  int quantitySold = 0;
  double revenue = 0;

  _ProductAgg({required this.productId, required this.variantId, required this.displayName});
}

class _CashierAgg {
  int transactionCount = 0;
  double revenue = 0;
}
