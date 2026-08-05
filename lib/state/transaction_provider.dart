import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/transaction.dart';

/// Transaction log for the Register screen. Backed by Supabase
/// (`transactions` + `transaction_line_items`, written atomically via
/// the `record_transaction` RPC). Wrap the app with
/// ChangeNotifierProvider<TransactionProvider> in main.dart to use this.
class TransactionProvider extends ChangeNotifier {
  final List<Transaction> _transactions = [];
  final _client = Supabase.instance.client;

  /// Newest first, for the Transactions tab list.
  List<Transaction> get transactions => List.unmodifiable(_transactions.reversed);

  bool get isEmpty => _transactions.isEmpty;

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

  /// Fetch-once-on-login, same pattern as ProductProvider.loadFromSupabase().
  /// Call this right after PIN sign-in, before the register screen shows.
  /// Nested select pulls each transaction's line items in the same request.
  Future<void> loadFromSupabase() async {
    final rows = await _client
        .from('transactions')
        .select('*, transaction_line_items(*)')
        .order('created_at');

    _transactions
      ..clear()
      ..addAll(rows.map<Transaction>((row) => _fromRow(row as Map<String, dynamic>)));
    notifyListeners();
  }

  /// Records a completed sale. Call this with the cart's items BEFORE
  /// clearing the cart, so quantities are still intact.
  ///
  /// Async — this now makes a network call (atomic insert of the
  /// transactions row + all line items via the record_transaction RPC).
  /// Callers must await this and handle a possible failure (network
  /// drop, RLS reject) before clearing the cart or navigating away.
  Future<Transaction> record({
    required List<CartItem> cartItems,
    required double total,
    required double cashTendered,
    required double change,
  }) async {
    final lineItems = cartItems.map(TransactionLineItem.fromCartItem).toList();
    final itemsJson = lineItems
        .map((li) => {
              'product_id': li.productId,
              'product_name': li.name,
              'category': li.category,
              'unit_price': li.price,
              'quantity': li.quantity,
              'line_total': li.lineTotal,
            })
        .toList();

    final row = await _client.rpc('record_transaction', params: {
      'p_total': total,
      'p_cash_tendered': cashTendered,
      'p_change_amount': change,
      'p_cashier_name': null, // TODO: wire up once cashier identity is decided
      'p_items': itemsJson,
    }).single();

    final transaction = Transaction(
      id: row['id'] as String,
      transactionNumber: '#${(row['transaction_number'] as int).toString().padLeft(5, '0')}',
      timestamp: DateTime.parse(row['created_at'] as String),
      items: lineItems,
      total: total,
      cashTendered: cashTendered,
      change: change,
    );

    _transactions.add(transaction);
    notifyListeners();
    return transaction;
  }

  Transaction _fromRow(Map<String, dynamic> row) {
    final lineRows = (row['transaction_line_items'] as List).cast<Map<String, dynamic>>();
    return Transaction(
      id: row['id'] as String,
      transactionNumber: '#${(row['transaction_number'] as int).toString().padLeft(5, '0')}',
      timestamp: DateTime.parse(row['created_at'] as String),
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
              ))
          .toList(),
      total: (row['total'] as num).toDouble(),
      cashTendered: (row['cash_tendered'] as num).toDouble(),
      change: (row['change_amount'] as num).toDouble(),
    );
  }
}
