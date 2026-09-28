import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_table.dart';

/// Thrown by [TableProvider.addTable] when a table with that label
/// already exists for this store — mirrors the unique(store_id, label)
/// constraint from the QR-ordering migration (error code 23505).
class DuplicateTableLabelException implements Exception {
  final String message;
  const DuplicateTableLabelException(this.message);

  @override
  String toString() => message;
}

/// Backs the Tables admin panel (Settings → Tables). Each row maps to
/// the `tables` Supabase table from the QR-ordering migration
/// (20260928_020_qr_ordering_core.sql): id, store_id, label, qr_token,
/// is_active.
///
/// store_id is never set from here on insert — same convention as
/// ProductProvider's category insert (`.insert({'name': trimmed})`
/// with no store_id) — it relies on tables.store_id defaulting via
/// current_store_id() server-side. See
/// 20260928_021_tables_store_id_default.sql, which adds that default
/// (the original QR-ordering migration didn't have it yet).
class TableProvider extends ChangeNotifier {
  List<OrderTable> _tables = [];
  bool _loading = false;
  String? _error;

  List<OrderTable> get tables => List.unmodifiable(_tables);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadFromSupabase() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await Supabase.instance.client
          .from('tables')
          .select('id, label, qr_token, is_active')
          .eq('is_active', true)
          .order('label');

      _tables = (rows as List)
          .map((row) => OrderTable(
                id: row['id'] as String,
                label: row['label'] as String,
                qrToken: row['qr_token'] as String,
                isActive: row['is_active'] as bool,
              ))
          .toList();
    } catch (e) {
      _error = 'Could not load tables.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> addTable(String label) async {
    try {
      await Supabase.instance.client.from('tables').insert({'label': label});
      await loadFromSupabase();
    } catch (e) {
      if (e is PostgrestException && e.code == '23505') {
        throw DuplicateTableLabelException('A table named "$label" already exists.');
      }
      rethrow;
    }
  }

  /// Soft delete, same convention as UserProvider.deleteUser — keeps
  /// the row (and its qr_token / any order history against it) intact
  /// instead of a hard DELETE, since tables.id is referenced by
  /// orders.table_id with ON DELETE RESTRICT.
  Future<void> deactivateTable(String id) async {
    await Supabase.instance.client
        .from('tables')
        .update({'is_active': false})
        .eq('id', id);
    await loadFromSupabase();
  }
}
