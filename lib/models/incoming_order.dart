/// One line of a customer's QR order, as shown on the cashier's
/// Incoming Orders screen. `variantName` is the size/option the customer
/// picked (snapshotted on order_items at order time), null for products
/// without sizes.
class IncomingOrderItem {
  final String? productId;
  final String? variantId;
  final String name;
  final String? variantName;
  final int quantity;
  final double price; // unit price at order time

  const IncomingOrderItem({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.variantName,
    required this.quantity,
    required this.price,
  });

  double get lineTotal => price * quantity;

  String get displayName =>
      (variantName == null || variantName!.isEmpty) ? name : '$name · $variantName';

  /// Same "Coffee (Large)" style the Register uses for sale line names.
  String get saleName =>
      (variantName == null || variantName!.isEmpty) ? name : '$name ($variantName)';

  factory IncomingOrderItem.fromRow(Map<String, dynamic> row) {
    final product = row['products'];
    return IncomingOrderItem(
      productId: row['product_id'] as String?,
      variantId: row['variant_id'] as String?,
      name: (product is Map ? product['name'] as String? : null) ?? 'Item',
      variantName: row['variant_name'] as String?,
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      price: _toDouble(row['price']),
    );
  }
}

/// A customer order that arrived through a table's QR code (orders +
/// order_items + tables joined by PostgREST -- see IncomingOrderProvider).
///
/// status:         'pending' -> 'preparing' -> 'ready' -> 'completed'
///                 or 'rejected'. (The older 'accepted' value is read as
///                 'preparing'.)
/// paymentMethod:  'counter' | 'online'
/// paymentStatus:  'unpaid' | 'unverified' | 'paid'
///   - online orders arrive 'unverified': the customer typed a reference
///     number, but nothing has proven the money arrived until the
///     cashier checks their e-wallet and marks it received.
class IncomingOrder {
  final String id;
  final int? orderNumber; // short per-day queue number (#1, #2, ...)
  final String status;
  final double total;
  final String? customerName;
  final String tableLabel;
  final DateTime createdAt;
  final String paymentMethod;
  final String paymentStatus;
  final String? paymentReference;
  final String? transactionId; // the sale this order became, once completed
  final List<IncomingOrderItem> items;

  const IncomingOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.total,
    required this.customerName,
    required this.tableLabel,
    required this.createdAt,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.paymentReference,
    required this.transactionId,
    required this.items,
  });

  bool get isOnline => paymentMethod == 'online';
  bool get isPaid => paymentStatus == 'paid';

  /// First 8 characters of the id, upper-cased (fallback for orders
  /// placed before queue numbers existed).
  String get shortId => id.length <= 8 ? id.toUpperCase() : id.substring(0, 8).toUpperCase();

  /// What the customer sees on their phone: "#12".
  String get numberLabel => orderNumber != null ? '#$orderNumber' : '#$shortId';

  factory IncomingOrder.fromRow(Map<String, dynamic> row) {
    final table = row['tables'];
    final rawItems = row['order_items'];
    final rawStatus = row['status'] as String? ?? 'pending';
    return IncomingOrder(
      id: row['id'] as String,
      orderNumber: (row['order_number'] as num?)?.toInt(),
      status: rawStatus == 'accepted' ? 'preparing' : rawStatus,
      total: _toDouble(row['total']),
      customerName: row['customer_name'] as String?,
      tableLabel: (table is Map ? table['label'] as String? : null) ?? 'Table',
      createdAt: DateTime.parse(row['created_at'] as String),
      paymentMethod: row['payment_method'] as String? ?? 'counter',
      paymentStatus: row['payment_status'] as String? ?? 'unpaid',
      paymentReference: row['payment_reference'] as String?,
      transactionId: row['transaction_id'] as String?,
      items: rawItems is List
          ? rawItems
              .map((i) => IncomingOrderItem.fromRow(Map<String, dynamic>.from(i as Map)))
              .toList()
          : const [],
    );
  }
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}
