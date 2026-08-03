import 'package:flutter/foundation.dart';
import '../models/user.dart';

/// Holds the staff account list in memory — same as CartProvider,
/// ProductProvider, and TransactionProvider, this is temporary until the
/// Supabase integration replaces it with real persistence (and real Auth).
///
/// Seeded with one admin account so the app is never left with zero users
/// and the Users panel always has at least one row to show.
class UserProvider extends ChangeNotifier {
  final List<AppUser> _users = [
    AppUser(id: 'u1', name: 'Admin', role: UserRole.admin, pin: '1234'),
  ];

  int _nextId = 2;

  List<AppUser> get users => List.unmodifiable(_users);

  void addUser({
    required String name,
    required UserRole role,
    required String pin,
  }) {
    _users.add(AppUser(id: 'u${_nextId++}', name: name, role: role, pin: pin));
    notifyListeners();
  }

  void updateUser(
    String id, {
    String? name,
    UserRole? role,
    String? pin,
  }) {
    final index = _users.indexWhere((u) => u.id == id);
    if (index == -1) return;
    _users[index] = _users[index].copyWith(name: name, role: role, pin: pin);
    notifyListeners();
  }

  void deleteUser(String id) {
    _users.removeWhere((u) => u.id == id);
    notifyListeners();
  }
}
