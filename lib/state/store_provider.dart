import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store.dart';

/// The signed-in owner's store record -- business_type (drives the
/// Inventory screen's label), plan/trial state (Settings, Upgrade
/// screen), AI Assistant credit balance (AI Assistant tab), the
/// Senior/PWD discount feature toggle (Settings, Checkout modal), and
/// Store Details / Receipt Details fields (name/address/receipt
/// footer/TIN/contact number/permit number).
///
/// Load pattern matches ProductProvider/UserProvider: fetch-once-on-
/// login, not realtime. Call [loadFromSupabase] right after a
/// successful sign-in and before showing HomeShell; nothing
/// auto-refreshes after that until the next login, except
/// [setAiCreditsRemaining] (called after every AI Assistant reply),
/// [setSeniorPwdDiscountEnabled] (called when the owner flips the
/// Settings toggle), and [updateStoreDetails] (called on Save from the
/// Store Details screen) which all update the in-memory store
/// immediately so the UI never waits on a full reload.
///
/// RLS scopes the `stores` row to the caller automatically (same
/// current_store_id()-based policy as categories/products/staff_users),
/// so this is a plain single() select, no explicit store_id filter
/// needed here.
///
/// Every write to `stores` goes through [_updateStoreRow], which
/// throws if the update matched no rows. Without that check, an RLS
/// policy (or column grant) that blocks the write fails SILENTLY --
/// Supabase returns success with zero rows -- and the UI would show
/// "Saved" while nothing was persisted.
class StoreProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  Store? _store;
  bool isLoading = false;
  Object? loadError;

  Store? get store => _store;

  /// 'Raw Materials' (the safe default) until the store has loaded, so
  /// any screen reading this before login/load completes gets a sane
  /// label instead of null-checking everywhere.
  String get businessTypeLabel => _store?.businessTypeLabel ?? 'Raw Materials';

  /// False until the store has loaded -- defaults open, not locked,
  /// so a slow/failed load never accidentally banner-locks a real
  /// active store. True once the store's plan == 'expired' (manual
  /// testing override) or its real plan_expires_at date has passed --
  /// see Store.isExpired.
  bool get isExpired => _store?.isExpired ?? false;

  /// False until the store has loaded, matching every other flag on
  /// this provider — a slow/failed load must never make the discount
  /// option flash into view before the real (likely-off) value
  /// arrives, so this defaults closed, not open.
  bool get seniorPwdDiscountEnabled => _store?.seniorPwdDiscountEnabled ?? false;

  /// Same defaults-closed reasoning as seniorPwdDiscountEnabled above —
  /// no receipt preview should flash into view before the real
  /// (likely-off) value has loaded.
  bool get receiptPrintingEnabled => _store?.receiptPrintingEnabled ?? false;

  /// Runs an UPDATE on the caller's `stores` row and throws a
  /// [StateError] if it matched no rows (RLS policy missing, or the
  /// store id isn't visible to the caller). Also surfaces column-grant
  /// failures, which come back as a normal PostgrestException
  /// ("permission denied for table stores").
  Future<void> _updateStoreRow(String storeId, Map<String, dynamic> values) async {
    final res = await _client
        .from('stores')
        .update(values)
        .eq('id', storeId)
        .select('id');
    if ((res as List).isEmpty) {
      throw StateError(
        'Store update matched no rows (RLS?): ${values.keys.join(', ')}',
      );
    }
  }

  Future<void> loadFromSupabase() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final row = await _client
          .from('stores')
          .select(
            'id, name, business_type, plan, plan_expires_at, '
            'ai_credits_remaining, ai_credits_reset_at, '
            'senior_pwd_discount_enabled, receipt_printing_enabled, '
            'address, receipt_footer, tin, contact_number, permit_number, '
            'qr_pay_counter_enabled, qr_pay_online_enabled, '
            'online_payment_qr_url, online_payment_instructions',
          )
          .single();
      _store = Store.fromRow(row);
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      loadError = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Sets the credit count to the server's authoritative value, sent
  /// back on every successful ai-assistant response. Replaces the old
  /// optimistic "minus 1" local guess -- that could drift from the
  /// real server-side count (e.g. if a credit was consumed server-side
  /// but the client threw before reaching its own decrement step), so
  /// the UI now always reflects exactly what Supabase says is left.
  void setAiCreditsRemaining(int value) {
    if (_store == null) return;
    _store = _store!.copyWith(aiCreditsRemaining: value < 0 ? 0 : value);
    notifyListeners();
  }

  /// Flips the Senior/PWD discount toggle in Settings. Updates the UI
  /// immediately (optimistic — the toggle should feel instant, same
  /// as any other Switch), then persists to Supabase. On failure, the
  /// local value is rolled back and the error rethrown so the Settings
  /// screen can show it — silently drifting from what's actually
  /// saved would be worse than a visible revert here.
  Future<void> setSeniorPwdDiscountEnabled(bool value) async {
    final current = _store;
    if (current == null) return;

    _store = current.copyWith(seniorPwdDiscountEnabled: value);
    notifyListeners();

    try {
      await _updateStoreRow(current.id, {'senior_pwd_discount_enabled': value});
    } catch (e) {
      _store = current; // revert
      notifyListeners();
      rethrow;
    }
  }

  /// Flips the receipt printing toggle in Settings. Same optimistic-
  /// update-then-persist-then-rollback-on-failure shape as
  /// setSeniorPwdDiscountEnabled above.
  Future<void> setReceiptPrintingEnabled(bool value) async {
    final current = _store;
    if (current == null) return;

    _store = current.copyWith(receiptPrintingEnabled: value);
    notifyListeners();

    try {
      await _updateStoreRow(current.id, {'receipt_printing_enabled': value});
    } catch (e) {
      _store = current; // revert
      notifyListeners();
      rethrow;
    }
  }

  /// Saves the Store Details form — name/address/receipt footer plus
  /// the Receipt Details section (TIN/contact number/permit number).
  /// Not optimistic like the toggle above — this is a multi-field form
  /// with a real Save button, so the screen already has a natural
  /// loading state to show while this is in flight; better to only
  /// update local state once the write actually succeeds than to
  /// flash a save and then have to roll six fields back at once on
  /// failure.
  ///
  /// Every nullable param passed as null means "clear this field", not
  /// "leave unchanged" — the caller (StoreDetailsPanel) always sends
  /// the current text field contents, including empty strings
  /// converted to null, so this always reflects exactly what's on
  /// screen when Save is tapped.
  Future<void> updateStoreDetails({
    required String name,
    String? address,
    String? receiptFooter,
    String? tin,
    String? contactNumber,
    String? permitNumber,
  }) async {
    final current = _store;
    if (current == null) return;

    await _updateStoreRow(current.id, {
      'name': name,
      'address': address,
      'receipt_footer': receiptFooter,
      'tin': tin,
      'contact_number': contactNumber,
      'permit_number': permitNumber,
    });

    _store = current.copyWith(
      name: name,
      address: address,
      receiptFooter: receiptFooter,
      tin: tin,
      contactNumber: contactNumber,
      permitNumber: permitNumber,
      clearAddress: address == null,
      clearReceiptFooter: receiptFooter == null,
      clearTin: tin == null,
      clearContactNumber: contactNumber == null,
      clearPermitNumber: permitNumber == null,
    );
    notifyListeners();
  }

  /// Saves Settings -> QR Order Payments: which options customers see on
  /// the QR ordering page plus the optional instructions text. Not
  /// optimistic -- the panel has a real Save button and its own loading
  /// state, so local state only changes once the write succeeds.
  Future<void> updateQrPayments({
    required bool counterEnabled,
    required bool onlineEnabled,
    String? instructions,
  }) async {
    final current = _store;
    if (current == null) return;

    await _updateStoreRow(current.id, {
      'qr_pay_counter_enabled': counterEnabled,
      'qr_pay_online_enabled': onlineEnabled,
      'online_payment_instructions': instructions,
    });

    _store = current.copyWith(
      qrPayCounterEnabled: counterEnabled,
      qrPayOnlineEnabled: onlineEnabled,
      onlinePaymentInstructions: instructions,
      clearOnlinePaymentInstructions: instructions == null,
    );
    notifyListeners();
  }

  /// Uploads the store's own payment QR image (GCash/Maya/bank QR Ph) to
  /// the same public bucket product photos use, under the same
  /// `<auth uid>/` folder convention so the existing Storage policy
  /// applies. upsert + a cache-busting query param, same reasoning as
  /// ProductProvider._uploadProductImage.
  Future<void> uploadOnlinePaymentQr(Uint8List bytes) async {
    final current = _store;
    if (current == null) return;

    final uid = _client.auth.currentUser!.id;
    final path = '$uid/payment-qr.jpg';
    await _client.storage.from('product-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    final baseUrl = _client.storage.from('product-images').getPublicUrl(path);
    final url = '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';

    await _updateStoreRow(current.id, {'online_payment_qr_url': url});

    _store = current.copyWith(onlinePaymentQrUrl: url);
    notifyListeners();
  }

  /// Clears the QR and switches online payments off with it -- the QR
  /// ordering page only offers "Pay online" while a QR exists.
  Future<void> removeOnlinePaymentQr() async {
    final current = _store;
    if (current == null) return;

    await _updateStoreRow(current.id, {
      'online_payment_qr_url': null,
      'qr_pay_online_enabled': false,
    });

    _store = current.copyWith(
      clearOnlinePaymentQrUrl: true,
      qrPayOnlineEnabled: false,
    );
    notifyListeners();
  }
}
