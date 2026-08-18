import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store.dart';

/// The signed-in owner's store record -- business_type (drives the
/// Inventory screen's label), plan/trial state (Settings, Upgrade
/// screen), and AI Assistant credit balance (AI Assistant tab).
///
/// Load pattern matches ProductProvider/UserProvider: fetch-once-on-
/// login, not realtime. Call [loadFromSupabase] right after a
/// successful sign-in and before showing HomeShell; nothing
/// auto-refreshes after that until the next login, except
/// [setAiCreditsRemaining] which is called with the server's real
/// count after every AI Assistant reply (see
/// AiAssistantProvider.sendMessage) so the header credit count stays
/// accurate without trusting a local guess.
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

  Future<void> loadFromSupabase() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final row = await _client
          .from('stores')
          .select(
            'id, name, business_type, plan, plan_expires_at, '
            'ai_credits_remaining, ai_credits_reset_at',
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
}
