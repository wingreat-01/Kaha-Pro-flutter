/// A staff account — cashier or admin.
///
/// Auth itself is still the Phase 5 placeholder (login_screen.dart accepts
/// any non-empty username/password) — this model just gives Phase 4's
/// Users admin panel something real to manage ahead of that, and ahead of
/// Supabase Auth eventually replacing the whole login flow. The `pin` field
/// is a placeholder passcode, not a real credential — don't treat it as
/// secure storage.
enum UserRole { admin, cashier }

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.cashier:
        return 'Cashier';
    }
  }
}

class AppUser {
  final String id;
  String name;
  UserRole role;
  String pin;

  AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.pin,
  });

  AppUser copyWith({String? name, UserRole? role, String? pin}) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      pin: pin ?? this.pin,
    );
  }
}
