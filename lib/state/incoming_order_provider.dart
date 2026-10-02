import 'dart:async';
import 'package:flutter/widgets.dart';
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
class IncomingOrderProvider extends ChangeNotifier with WidgetsBindingObserver {
  final SupabaseClient _client = Supabase.instance.client;

  RealtimeChannel? _channel;
  List<IncomingOrder> _orders = [];
  bool isLoading = false;
  Object? loadError;
  bool _hasLoadedOnce = false;
  bool _disposed = false;
  bool _observing = false;
  Timer? _pollTimer;
  int _loadSeq = 0;

  /// Fires with the freshly arrived pending orders (never the ones that
  /// were already waiting on first load). HomeShell listens to this to
  /// show an on-screen alert, whichever section the cashier is in.
  final StreamController<List<IncomingOrder>> _newOrdersController =
      StreamController<List<IncomingOrder>>.broadcast();
  Stream<List<IncomingOrder>> get newOrders => _newOrdersController.stream;

  /// Safety-net refresh while signed in, in case realtime events stop
  /// arriving (dropped websocket, backgrounded tab, table not published).
  static const Duration _pollEvery = Duration(seconds: 12);

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
  ///
  /// A websocket alone isn't reliable on phones or in a background
  /// browser tab, so the list is kept fresh three ways:
  ///   1. Realtime events (instant).
  ///   2. A reload whenever the channel (re)subscribes and whenever the
  ///      app or browser tab returns to the foreground.
  ///   3. A light poll as a safety net if events never arrive.
  Future<void> start() async {
    await stop();
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    await load();
    if (_disposed) return;
    _channel = _client
        .channel('incoming-orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => load(),
        )
        .subscribe((status, error) {
      if (_disposed) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        load(); // catch anything missed while (re)connecting
      } else if (error != null) {
        debugPrint('IncomingOrderProvider realtime $status: $error');
      }
    });
    _pollTimer = Timer.periodic(_pollEvery, (_) => load());
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  String _signature(List<IncomingOrder> list) =>
      list.map((o) => '${o.id}|${o.status}|${o.paymentStatus}|${o.items.length}').join(',');

  /// Last two days of orders, newest first. Older ones aren't useful on
  /// a cashier screen and would just grow the list forever.
  ///
  /// Called from realtime events, the poll and app resume, so calls can
  /// overlap: only the newest call's result is applied, and listeners
  /// are only notified when something actually changed (the poll would
  /// otherwise rebuild HomeShell every few seconds for nothing).
  Future<void> load() async {
    if (_disposed) return;
    final seq = ++_loadSeq;
    final wasLoading = isLoading;
    final hadError = loadError != null;
    if (!_hasLoadedOnce) {
      isLoading = true;
      notifyListeners();
    }
    var changed = false;
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

      if (_disposed || seq != _loadSeq) return; // a newer load superseded this one

      final next = (rows as List)
          .map((r) => IncomingOrder.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();

      changed = _signature(next) != _signature(_orders);
      final knownIds = _orders.map((o) => o.id).toSet();
      _orders = next;
      // Alert only for pending orders that arrive while the app is open,
      // not for the ones already waiting when it first loads. Comparing
      // ids (not counts) means an accept/reject elsewhere can't mask a
      // new arrival, and a status change never re-triggers the alert.
      if (_hasLoadedOnce) {
        final fresh = next
            .where((o) => o.status == 'pending' && !knownIds.contains(o.id))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (fresh.isNotEmpty) {
          SystemSound.play(SystemSoundType.alert);
          if (!_newOrdersController.isClosed) _newOrdersController.add(fresh);
        }
      }
      _hasLoadedOnce = true;
      loadError = null;
    } catch (e) {
      if (_disposed || seq != _loadSeq) return;
      loadError = e;
      debugPrint('IncomingOrderProvider.load failed: $e');
    }
    isLoading = false;
    if (_disposed) return;
    if (changed || wasLoading || hadError || loadError != null) notifyListeners();
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
    _newOrdersController.close();
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      _client.removeChannel(channel);
    }
    super.dispose();
  }
}
