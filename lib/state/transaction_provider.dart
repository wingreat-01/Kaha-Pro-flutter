import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/pending_sale.dart';
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
        .select('*, transaction_line_items(*)')
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
  }) async {
    final lineItems = cartItems.map(TransactionLineItem.fromCartItem).toList();

    try {
      final row = await _client.rpc('record_transaction', params: {
        'p_total': total,
        'p_cash_tendered': cashTendered,
        'p_change_amount': change,
        'p_cashier_name': cashierName,
        'p_items': _itemsJson(lineItems),
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
  }) {
    final pending = PendingSale(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      total: total,
      cashTendered: cashTendered,
      change: change,
      cashierName: cashierName,
      items: lineItems,
      queuedAt: DateTime.now(),
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
    );
  }
}
