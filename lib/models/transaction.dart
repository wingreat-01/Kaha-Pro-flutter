import 'cart_item.dart';

/// A snapshot of one cart line at the moment of sale — copied out of
/// CartItem/Product rather than referenced, so a later product edit or
/// delete never changes a past transaction's record.
class TransactionLineItem {
  final String productId;
  final String name; // includes the size, e.g. "Coffee (Large)" — see
                      // TransactionLineItem.fromCartItem
  final double price; // unit price actually charged — the variant's
                       // price when one was selected, else the
                       // product's own flat price
  final int quantity;
  final String category;
  // Size snapshot, present only when a variant was selected. Kept
  // separately from `name` (which already has the size baked in for
  // display) so sales-by-size reporting doesn't have to parse it back
  // out of the combined name string. Both stay put even if the size
  // is later renamed or deleted — variant_id -> null via ON DELETE
  // SET NULL, but variant_name/name (the text snapshot) never changes.
  final String? variantId;
  final String? variantName;

  const TransactionLineItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
    this.variantId,
    this.variantName,
  });

  double get lineTotal => price * quantity;

  factory TransactionLineItem.fromCartItem(CartItem item) {
    return TransactionLineItem(
      productId: item.product.id,
      name: item.displayName,
      price: item.unitPrice,
      quantity: item.quantity,
      category: item.product.category,
      variantId: item.selectedVariant?.id,
      variantName: item.selectedVariant?.name,
    );
  }
}

/// A completed sale, logged by TransactionProvider when checkout is
/// confirmed. transactionNumber is the ledger-style identifier shown
/// in the Transactions tab (e.g. "#00001").
class Transaction {
  final String? id; // Supabase row id — null until this sale has synced
  final String? localId; // set only on unsynced rows — matches a PendingSale
  final String? cashierName; // null on older rows recorded before this was captured
  final String transactionNumber;
  final DateTime timestamp;
  final List<TransactionLineItem> items;
  final double total; // the amount actually collected — already net of
                       // any Senior/PWD discount (see discountAmount)
  final double cashTendered;
  final double change;
  final String? paymentMethodId; // FK snapshot — null on rows recorded before this feature
  final String? paymentMethodName; // display snapshot, since a method can be renamed/deleted later
  // Senior Citizen / PWD discount (RA 9994 / RA 10754) snapshot — null
  // discountType means no discount was applied to this sale. All null/
  // zero on rows recorded before this feature existed.
  final String? discountType; // 'senior' | 'pwd' | null
  final String? discountHolderName;
  final String? discountIdNumber;
  final double discountAmount; // 20% discount amount, already subtracted from `total`
  final double vatExemptAmount; // VAT portion removed from the gross price, informational

  const Transaction({
    this.id,
    this.localId,
    this.cashierName,
    required this.transactionNumber,
    required this.timestamp,
    required this.items,
    required this.total,
    required this.cashTendered,
    required this.change,
    this.paymentMethodId,
    this.paymentMethodName,
    this.discountType,
    this.discountHolderName,
    this.discountIdNumber,
    this.discountAmount = 0,
    this.vatExemptAmount = 0,
  });

  /// True for a sale that's been recorded locally (queued while
  /// offline) but hasn't reached Supabase yet.
  bool get isPending => id == null;

  bool get hasDiscount => discountType != null;

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
