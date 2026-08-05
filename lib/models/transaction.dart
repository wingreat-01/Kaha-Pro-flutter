import 'cart_item.dart';

/// A snapshot of one cart line at the moment of sale — copied out of
/// CartItem/Product rather than referenced, so a later product edit or
/// delete never changes a past transaction's record.
class TransactionLineItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final String category;

  const TransactionLineItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
  });

  double get lineTotal => price * quantity;

  factory TransactionLineItem.fromCartItem(CartItem item) {
    return TransactionLineItem(
      productId: item.product.id,
      name: item.product.name,
      price: item.product.price,
      quantity: item.quantity,
      category: item.product.category,
    );
  }
}

/// A completed sale, logged by TransactionProvider when checkout is
/// confirmed. transactionNumber is the ledger-style identifier shown
/// in the Transactions tab (e.g. "#00001").
class Transaction {
  final String? id; // Supabase row id — null only if somehow unsynced
  final String transactionNumber;
  final DateTime timestamp;
  final List<TransactionLineItem> items;
  final double total;
  final double cashTendered;
  final double change;

  const Transaction({
    this.id,
    required this.transactionNumber,
    required this.timestamp,
    required this.items,
    required this.total,
    required this.cashTendered,
    required this.change,
  });

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
}

/// Aggregated rollup of every transaction on one calendar day. `day` is
/// truncated to just year/month/day (no time component) so it can be
/// used as a stable grouping key. `transactions` keeps the same
/// newest-first order as TransactionProvider.transactions.
class DaySummary {
  final DateTime day;
  final List<Transaction> transactions;

  const DaySummary({required this.day, required this.transactions});

  double get totalRevenue => transactions.fold(0.0, (sum, t) => sum + t.total);
  int get saleCount => transactions.length;
  int get itemsSold => transactions.fold(0, (sum, t) => sum + t.itemCount);
}
