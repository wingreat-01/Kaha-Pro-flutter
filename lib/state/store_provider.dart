import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store.dart';

/// The signed-in owner's store record -- business_type (drives the
/// Inventory screen's label), plan/trial state (Settings, Upgrade
/// screen), AI Assistant credit balance (AI Assistant tab), the
/// Senior/PWD discount feature toggle (Settings, Checkout modal), and
/// Store Details fields (name/address/receipt footer).
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
            'senior_pwd_discount_enabled, address, receipt_footer',
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
      await _client
          .from('stores')
          .update({'senior_pwd_discount_enabled': value})
          .eq('id', current.id);
    } catch (e) {
      _store = current; // revert
      notifyListeners();
      rethrow;
    }
  }

  /// Saves the Store Details form (name/address/receipt footer). Not
  /// optimistic like the toggle above — this is a multi-field form
  /// with a real Save button, so the screen already has a natural
  /// loading state to show while this is in flight; better to only
  /// update local state once the write actually succeeds than to
  /// flash a save and then have to roll three fields back at once on
  /// failure.
  ///
  /// [address]/[receiptFooter] passed as null mean "clear this field",
  /// not "leave unchanged" — the caller (StoreDetailsPanel) always
  /// sends the current text field contents, including empty strings
  /// converted to null, so this always reflects exactly what's on
  /// screen when Save is tapped.
  Future<void> updateStoreDetails({
    required String name,
    String? address,
    String? receiptFooter,
  }) async {
    final current = _store;
    if (current == null) return;

    await _client.from('stores').update({
      'name': name,
      'address': address,
      'receipt_footer': receiptFooter,
    }).eq('id', current.id);

    _store = current.copyWith(
      name: name,
      address: address,
      receiptFooter: receiptFooter,
      clearAddress: address == null,
      clearReceiptFooter: receiptFooter == null,
    );
    notifyListeners();
  }
}
