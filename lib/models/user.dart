/// A staff account — cashier or admin.
///
/// `pin` is optional and defaults to empty. It used to be required back
/// when this model was the Phase 5 placeholder standing in for real
/// auth (see the old comment below) — now that login_screen.dart
/// authenticates against verify_staff_login() and builds this object
/// from the RPC result, there's no reason to carry the PIN around in
/// memory after a successful sign-in, so nothing sets it anymore.
/// Left in (rather than deleted) in case Phase 4's Users admin panel
/// still references it when editing staff records — worth confirming
/// and removing outright if not.
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
    this.pin = '',
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
