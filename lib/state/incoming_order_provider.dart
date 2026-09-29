import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/incoming_order.dart';

/// Orders customers send from a table's QR page (order.html), kept live
/// with Supabase Realtime so the cashier sees them without refreshing.
///
/// Order flow: pending -> preparing -> ready -> completed (or rejected).
/// The customer's phone follows the same status through the
/// get_order_status RPC, so every change made here shows up there.
///
/// HomeShell calls [start] when it mounts and [stop] when it goes away.
/// Realtime is only used as a "something changed" signal -- every event
/// simply reloads the list, because order_items rows aren't in the
/// realtime publication and a reload is cheap at this volume.
///
/// RLS scopes `orders` (and its joined tables) to the signed-in owner's
/// store, so no explicit store_id filter is needed here -- same
/// assumption as StoreProvider / ProductProvider.
class IncomingOrderProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  RealtimeChannel? _channel;
  List<IncomingOrder> _orders = [];
  bool isLoading = false;
  Object? loadError;
  bool _hasLoadedOnce = false;
  bool _disposed = false;

  /// orderId -> transaction id, for sales already recorded from an order
  /// during this session. If saving the sale worked but flipping the
  /// order to "completed" failed, tapping Complete again must NOT record
  /// a second sale -- it only retries the status update.
  final Map<String, String?> _recordedSales = {};

  List<IncomingOrder> get orders => _orders;

  // Active queues, oldest first (first come, first served).
  List<IncomingOrder> get pending => _byStatus(['pending']);
  List<IncomingOrder> get preparing => _byStatus(['preparing']);
  List<IncomingOrder> get ready => _byStatus(['ready']);

  /// Completed / rejected, newest first.
  List<IncomingOrder> get done =>
      _orders.where((o) => o.status == 'completed' || o.status == 'rejected').toList();

  int get pendingCount => pending.length;

  List<IncomingOrder> _byStatus(List<String> statuses) {
    final list = _orders.where((o) => statuses.contains(o.status)).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  bool hasRecordedSale(String orderId) => _recordedSales.containsKey(orderId);
  String? recordedSaleId(String orderId) => _recordedSales[orderId];
  void rememberSale(String orderId, String? transactionId) =>
      _recordedSales[orderId] = transactionId;

  /// Safe to call repeatedly (a new HomeShell after every PIN login
  /// calls it again) -- any old subscription is closed first.
  Future<void> start() async {
    await stop();
    await load();
    _channel = _client
        .channel('incoming-orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => load(),
        )
        .subscribe();
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
  }

  /// Last two days of orders, newest first. Older ones aren't useful on
  /// a cashier screen and would just grow the list forever.
  Future<void> load() async {
    if (_disposed) return;
    if (!_hasLoadedOnce) {
      isLoading = true;
      notifyListeners();
    }
    try {
      final since = DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String();
      final rows = await _client
          .from('orders')
          .select(
            'id, order_number, status, total, customer_name, created_at, '
            'payment_method, payment_status, payment_reference, transaction_id, '
            'tables(label), '
            'order_items(product_id, variant_id, quantity, price, variant_name, products(name))',
          )
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(100);

      final next = (rows as List)
          .map((r) => IncomingOrder.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();

      final before = pendingCount;
      _orders = next;
      // Audible nudge only for orders that arrive while the app is open,
      // not for the ones already waiting when it first loads.
      if (_hasLoadedOnce && pendingCount > before) {
        SystemSound.play(SystemSoundType.alert);
      }
      _hasLoadedOnce = true;
      loadError = null;
    } catch (e) {
      loadError = e;
      debugPrint('IncomingOrderProvider.load failed: $e');
    }
    isLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Accept = the kitchen starts on it.
  Future<void> accept(IncomingOrder order) => _update(order.id, {'status': 'preparing'});

  Future<void> reject(IncomingOrder order) => _update(order.id, {'status': 'rejected'});

  /// Food/drink is done -- the customer's phone switches to "Now serving".
  Future<void> markReady(IncomingOrder order) => _update(order.id, {'status': 'ready'});

  /// The cashier has confirmed the money arrived (checked their e-wallet
  /// for an online order, or took payment at the counter).
  Future<void> markPaid(IncomingOrder order) => _update(order.id, {'payment_status': 'paid'});

  /// Final step: the order has been rung up as a sale ([transactionId]
  /// is null only when that sale was queued offline and hasn't synced).
  Future<void> complete(IncomingOrder order, {String? transactionId}) => _update(order.id, {
        'status': 'completed',
        'payment_status': 'paid',
        if (transactionId != null) 'transaction_id': transactionId,
      });

  Future<void> _update(String id, Map<String, dynamic> patch) async {
    final res = await _client
        .from('orders')
        .update({...patch, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id');
    // An RLS-blocked update returns zero rows instead of throwing; surface
    // that rather than pretending the tap worked.
    if ((res as List).isEmpty) {
      throw StateError('The order could not be updated.');
    }
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      _client.removeChannel(channel);
    }
    super.dispose();
  }
}
