import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store.dart';

/// The signed-in owner's store record -- currently just business_type,
/// which drives the Inventory screen's label ("Ingredients" /
/// "Supplies" / "Raw Materials", see kahapro-inventory-recipes-plan.md
/// Step 0).
///
/// Load pattern matches ProductProvider/UserProvider: fetch-once-on-
/// login, not realtime. Call [loadFromSupabase] right after a
/// successful sign-in and before showing HomeShell; nothing
/// auto-refreshes after that until the next login.
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

  Future<void> loadFromSupabase() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final row = await _client
          .from('stores')
          .select('id, name, business_type')
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
}
