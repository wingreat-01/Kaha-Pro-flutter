import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../models/transaction.dart';

/// Transaction log for the Register screen. In-memory for now — Phase 3
/// is expected to back this with persisted storage. Wrap the app with
/// ChangeNotifierProvider<TransactionProvider> in main.dart to use this.
class TransactionProvider extends ChangeNotifier {
  final List<Transaction> _transactions = [];
  int _counter = 0;

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

  /// Records a completed sale. Call this with the cart's items BEFORE
  /// clearing the cart, so quantities are still intact.
  Transaction record({
    required List<CartItem> cartItems,
    required double total,
    required double cashTendered,
    required double change,
  }) {
    _counter += 1;
    final transaction = Transaction(
      transactionNumber: '#${_counter.toString().padLeft(5, '0')}',
      timestamp: DateTime.now(),
      items: cartItems.map(TransactionLineItem.fromCartItem).toList(),
      total: total,
      cashTendered: cashTendered,
      change: change,
    );
    _transactions.add(transaction);
    notifyListeners();
    return transaction;
  }
}
