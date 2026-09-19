import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Receipt display options. Saved per-device via shared_preferences —
/// the same approach as PrinterProvider and CurrencyProvider — so each
/// register/tablet decides for itself how its receipts look.
class ReceiptOptionsProvider extends ChangeNotifier {
  static const _vatKey = 'receipt_show_vat_breakdown';

  /// Mirror of [showVatBreakdown] for code that has no BuildContext
  /// (the ESC/POS builder and the web print service). Widgets should
  /// watch the provider instead.
  static bool vatBreakdownActive = false;

  bool _showVatBreakdown = false;

  /// Whether receipts list VATable Sales / VAT (12%) / Amount Due.
  /// Off by default — only VAT-registered businesses should show it.
  bool get showVatBreakdown => _showVatBreakdown;

  /// Register as `ReceiptOptionsProvider()..load()` in main.dart.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_vatKey) ?? false;
      if (saved != _showVatBreakdown) {
        _showVatBreakdown = saved;
        vatBreakdownActive = saved;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable — stay on the default rather than crash.
    }
  }

  Future<void> setShowVatBreakdown(bool value) async {
    if (value == _showVatBreakdown) return;
    _showVatBreakdown = value;
    vatBreakdownActive = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_vatKey, value);
    } catch (_) {
      // Not persisted this time; still applies for the current session.
    }
  }
}
