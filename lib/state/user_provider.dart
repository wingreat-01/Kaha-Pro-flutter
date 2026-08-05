import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';

/// Staff account list for the Users admin panel -- now backed by
/// Supabase's staff_users table instead of an in-memory seed list.
///
/// PINs are never fetched back from Supabase (only pin_hash is stored
/// server-side, and it never comes down to the client). AppUser.pin
/// stays '' for every row loaded here -- the Add/Edit form's PIN field
/// only ever holds a real PIN transiently, on its way to being hashed
/// server-side by add_staff_user() / update_staff_user().
class UserProvider extends ChangeNotifier {
  List<AppUser> _users = [];
  bool _loading = false;
  String? _error;

  List<AppUser> get users => List.unmodifiable(_users);
  bool get loading => _loading;
  String? get error => _error;

  UserRole _parseRole(String? raw) {
    return UserRole.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => UserRole.cashier,
    );
  }

  Future<void> loadFromSupabase() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await Supabase.instance.client
          .from('staff_users')
          .select('id, name, role')
          .eq('is_active', true)
          .order('name');

      _users = (rows as List)
          .map((row) => AppUser(
                id: row['id'] as String,
                name: row['name'] as String,
                role: _parseRole(row['role'] as String?),
              ))
          .toList();
    } catch (e) {
      _error = 'Could not load users.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> addUser({
    required String name,
    required UserRole role,
    required String pin,
  }) async {
    await Supabase.instance.client.rpc('add_staff_user', params: {
      'staff_name': name,
      'pin': pin,
      'staff_role': role.name,
    });
    await loadFromSupabase();
  }

  /// Pass pin as null or '' to leave the existing PIN unchanged --
  /// the edit form only sends a pin when the person actually typed
  /// a new one.
  Future<void> updateUser(
    String id, {
    String? name,
    UserRole? role,
    String? pin,
  }) async {
    final existing = _users.firstWhere((u) => u.id == id);
    await Supabase.instance.client.rpc('update_staff_user', params: {
      'staff_id': id,
      'staff_name': name ?? existing.name,
      'staff_role': (role ?? existing.role).name,
      'pin': (pin == null || pin.isEmpty) ? null : pin,
    });
    await loadFromSupabase();
  }

  Future<void> deleteUser(String id) async {
    // Soft delete: is_active=false, matching what verify_staff_login()
    // already checks at login time. Keeps the row (and any foreign-key
    // history against it, e.g. logged transactions) intact instead of
    // a hard DELETE.
    await Supabase.instance.client
        .from('staff_users')
        .update({'is_active': false})
        .eq('id', id);
    await loadFromSupabase();
  }
}
