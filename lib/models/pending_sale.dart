import 'dart:convert';
import 'transaction.dart';

/// A sale that couldn't reach Supabase at checkout time — persisted
/// locally (so it survives an app restart) and retried on the next
/// successful sync. `localId` is a client-generated tag, not a
/// Supabase id — it's how TransactionProvider matches this queue
/// entry back to its placeholder Transaction once one exists, and
/// later swaps that placeholder for the real synced row.
class PendingSale {
  final String localId;
  final double total;
  final double cashTendered;
  final double change;
  final String? cashierName;
  final List<TransactionLineItem> items;
  final DateTime queuedAt;
  final String? paymentMethodId;
  final String? paymentMethodName;

  const PendingSale({
    required this.localId,
    required this.total,
    required this.cashTendered,
    required this.change,
    required this.cashierName,
    required this.items,
    required this.queuedAt,
    this.paymentMethodId,
    this.paymentMethodName,
  });

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'total': total,
        'cashTendered': cashTendered,
        'change': change,
        'cashierName': cashierName,
        'items': items
            .map((i) => {
                  'productId': i.productId,
                  'name': i.name,
                  'price': i.price,
                  'quantity': i.quantity,
                  'category': i.category,
                  'variantId': i.variantId,
                  'variantName': i.variantName,
                })
            .toList(),
        'queuedAt': queuedAt.toIso8601String(),
        'paymentMethodId': paymentMethodId,
        'paymentMethodName': paymentMethodName,
      };

  factory PendingSale.fromJson(Map<String, dynamic> json) => PendingSale(
        localId: json['localId'] as String,
        total: (json['total'] as num).toDouble(),
        cashTendered: (json['cashTendered'] as num).toDouble(),
        change: (json['change'] as num).toDouble(),
        cashierName: json['cashierName'] as String?,
        items: (json['items'] as List)
            .map((i) => TransactionLineItem(
                  productId: i['productId'] as String,
                  name: i['name'] as String,
                  price: (i['price'] as num).toDouble(),
                  quantity: i['quantity'] as int,
                  category: i['category'] as String,
                  variantId: i['variantId'] as String?,
                  variantName: i['variantName'] as String?,
                ))
            .toList(),
        queuedAt: DateTime.parse(json['queuedAt'] as String),
        // Absent on any queue entry persisted before this feature —
        // decode as null rather than throwing, same as cashierName's
        // existing nullable treatment above.
        paymentMethodId: json['paymentMethodId'] as String?,
        paymentMethodName: json['paymentMethodName'] as String?,
      );

  /// Whole-queue helpers, so TransactionProvider only ever does one
  /// SharedPreferences read/write for the entire queue, not one per
  /// entry — keeps a queue of several offline sales cheap to persist.
  static String encodeList(List<PendingSale> sales) =>
      jsonEncode(sales.map((s) => s.toJson()).toList());

  static List<PendingSale> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => PendingSale.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
