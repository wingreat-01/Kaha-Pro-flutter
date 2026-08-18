import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_method.dart';

class PaymentMethodProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<PaymentMethod> _paymentMethods = [];
  bool _isLoading = false;
  String? _error;

  List<PaymentMethod> get paymentMethods => _paymentMethods;

  /// Only the ones a cashier should be able to select at checkout.
  List<PaymentMethod> get activeMethods =>
      _paymentMethods.where((m) => m.isActive).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch-once-on-login, same as ProductProvider/IngredientProvider.
  /// Call again manually after admin edits (add/edit/delete/reorder).
  Future<void> loadFromSupabase() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabase
          .from('payment_methods')
          .select()
          .order('sort_order', ascending: true);

      _paymentMethods = (response as List)
          .map((row) => PaymentMethod.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = 'Failed to load payment methods: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addPaymentMethod(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    try {
      final nextSortOrder = _paymentMethods.isEmpty
          ? 0
          : _paymentMethods.map((m) => m.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

      final response = await _supabase
          .from('payment_methods')
          .insert({
            'name': trimmed,
            'sort_order': nextSortOrder,
          })
          .select()
          .single();

      _paymentMethods.add(PaymentMethod.fromMap(response));
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add payment method: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updatePaymentMethod(PaymentMethod method) async {
    try {
      await _supabase
          .from('payment_methods')
          .update(method.toMap())
          .eq('id', method.id);

      final index = _paymentMethods.indexWhere((m) => m.id == method.id);
      if (index != -1) {
        _paymentMethods[index] = method;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = 'Failed to update payment method: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setActive(String id, bool isActive) async {
    final index = _paymentMethods.indexWhere((m) => m.id == id);
    if (index == -1) return false;
    return updatePaymentMethod(_paymentMethods[index].copyWith(isActive: isActive));
  }

  Future<bool> deletePaymentMethod(String id) async {
    try {
      await _supabase.from('payment_methods').delete().eq('id', id);
      _paymentMethods.removeWhere((m) => m.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete payment method: $e';
      notifyListeners();
      return false;
    }
  }

  /// Persist new order after a drag-reorder in the admin screen.
  Future<void> reorder(List<PaymentMethod> newOrder) async {
    for (var i = 0; i < newOrder.length; i++) {
      if (newOrder[i].sortOrder != i) {
        await updatePaymentMethod(newOrder[i].copyWith(sortOrder: i));
      }
    }
  }
}
