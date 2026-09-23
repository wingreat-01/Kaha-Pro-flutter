import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';

/// Thrown by [UserProvider.addUser] when the store is at its plan's
/// staff cap — either caught locally before any network call (the
/// common case), or surfaced from the server-side
/// `enforce_staff_limit` Postgres trigger (errcode P0001) if the local
/// check and the server ever disagree (e.g. plan changed on another
/// device, or this session's plan hasn't loaded yet). Mirrors
/// ProductLimitExceededException / enforce_product_limit exactly —
/// see product_provider.dart.
class StaffLimitExceededException implements Exception {
  final String message;
  const StaffLimitExceededException(this.message);

  @override
  String toString() => message;
}

/// Staff account list for the Users admin panel -- now backed by
/// Supabase's staff_users table instead of an in-memory seed list.
///
/// PINs are never fetched back from Supabase (only pin_hash is stored
/// server-side, and it never comes down to the client). AppUser.pin
/// stays '' for every row loaded here -- the Add/Edit form's PIN field
/// only ever holds a real PIN transiently, on its way to being hashed
/// server-side by add_staff_user() / update_staff_user().
class UserProvider extends ChangeNotifier {
  /// Per-plan active-staff caps — mirrors the `staff_limit()` function
  /// backing the `enforce_staff_limit` trigger (see
  /// 20260923_020_enforce_staff_limit.sql). This copy is UI-only (for
  /// the live counter/lock in UsersPanel); the trigger is what
  /// actually enforces it. null = unlimited.
  static const Map<String, int?> _staffLimits = {
    'free': 1,
    'starter': 2,
    'basic': 5,
    'pro': null,
  };

  List<AppUser> _users = [];
  bool _loading = false;
  String? _error;

  /// Null until [loadFromSupabase] fetches it, or if that fetch fails.
  /// Treated as "unknown" rather than defaulting to 'free', same
  /// reasoning as ProductProvider._plan — a fetch hiccup shouldn't
  /// falsely lock a paying store out of adding staff in the UI; the
  /// trigger still enforces the real cap regardless.
  String? _plan;
  DateTime? _planExpiresAt;

  List<AppUser> get users => List.unmodifiable(_users);
  bool get loading => _loading;
  String? get error => _error;

  /// Same free-trial-is-unlimited treatment as
  /// ProductProvider._isInTrial, kept in sync with what
  /// enforce_staff_limit() does server-side.
  bool get _isInTrial =>
      _plan == 'free' && _planExpiresAt != null && DateTime.now().isBefore(_planExpiresAt!);

  /// This store's active-staff cap for its current plan. Null means
  /// unlimited (Pro, or a free-plan store still in its trial window)
  /// or the plan hasn't loaded yet.
  int? get staffLimit {
    if (_plan == null) return null;
    if (_isInTrial) return null;
    return _staffLimits[_plan];
  }

  int get activeStaffCount => _users.length;

  bool get isAtStaffLimit {
    final limit = staffLimit;
    return limit != null && activeStaffCount >= limit;
  }

  /// Null means unlimited (or plan not loaded). Never negative.
  int? get remainingStaffSlots {
    final limit = staffLimit;
    if (limit == null) return null;
    final remaining = limit - activeStaffCount;
    return remaining < 0 ? 0 : remaining;
  }

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
      // Drives the staff-count cap shown in the UI (staffLimit /
      // isAtStaffLimit above). Isolated in its own try/catch, same as
      // ProductProvider — a failure here shouldn't take down the
      // whole staff list, and leaving _plan null just means the UI
      // won't show a cap this session while enforce_staff_limit still
      // governs actual inserts.
      try {
        final storeRow = await Supabase.instance.client
            .from('stores')
            .select('plan, plan_expires_at')
            .single();
        _plan = storeRow['plan'] as String?;
        final expiresRaw = storeRow['plan_expires_at'] as String?;
        _planExpiresAt = expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
      } catch (e) {
        debugPrint('loadFromSupabase: could not fetch store plan: $e');
      }

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
    // Local pre-check — catches the common case instantly, no network
    // round trip. Not the real gate: the enforce_staff_limit trigger
    // is (see the catch block below), since this check can be stale
    // if the plan changed on another device or hasn't loaded this
    // session.
    if (isAtStaffLimit) {
      throw StaffLimitExceededException(
        'Staff limit reached for your plan ($staffLimit max). '
        'Upgrade to add more staff accounts.',
      );
    }

    try {
      await Supabase.instance.client.rpc('add_staff_user', params: {
        'staff_name': name,
        'pin': pin,
        'staff_role': role.name,
      });
      await loadFromSupabase();
    } catch (e) {
      // The real gate: enforce_staff_limit trigger rejects the insert
      // server-side (errcode P0001) if the local pre-check above was
      // stale — e.g. another device added the last slot in the gap
      // between the check and this request landing.
      if (e is PostgrestException && e.code == 'P0001') {
        throw StaffLimitExceededException(e.message);
      }
      rethrow;
    }
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
