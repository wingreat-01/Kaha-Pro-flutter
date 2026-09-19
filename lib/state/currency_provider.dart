import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/currency.dart';

/// Which currency the store displays amounts in. Saved per-device via
/// shared_preferences (same approach as PrinterProvider) — if it should
/// follow the store across devices, move it to a `currency_code`
/// column on `stores` and have load()/setCurrency() read/write that
/// instead; nothing else in the app needs to change.
///
/// Changing currency only changes how amounts are *displayed*. Prices
/// and past transactions are stored as plain numbers and are not
/// converted.
class CurrencyProvider extends ChangeNotifier {
  static const _prefsKey = 'currency_code';

  /// Mirror of the current currency for code that has no BuildContext
  /// (the receipt printers in the services layer). Widgets should use
  /// the `context.money(...)` helpers below instead.
  static Currency active = Currencies.php;

  Currency _currency = Currencies.php;
  Currency get currency => _currency;

  /// Register as `CurrencyProvider()..load()` in main.dart's MultiProvider.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = Currencies.byCode(prefs.getString(_prefsKey));
      if (saved.code != _currency.code) {
        _currency = saved;
        active = saved;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable — stay on the default rather than crash.
    }
  }

  Future<void> setCurrency(Currency next) async {
    if (next.code == _currency.code) return;
    _currency = next;
    active = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.code);
    } catch (_) {
      // Not persisted this time; still applies for the current session.
    }
  }
}

/// One-line money formatting for widgets.
///
/// `money`, `moneyPlain`, `moneyPrefix`, `moneySymbol` and `moneyHint`
/// listen to the provider, so call them from build() (or a helper that
/// build() calls) and the UI refreshes when the currency changes. In
/// event handlers (onPressed, async methods) use [currencyRead], which
/// reads once without listening.
extension MoneyContext on BuildContext {
  Currency get _watched => Provider.of<CurrencyProvider>(this).currency;

  /// "₱1250.00", "-₱50.00", "Rp 15000"
  String money(num amount) => _watched.format(amount);

  /// "1250.00" — number only, for receipt columns.
  String moneyPlain(num amount) => _watched.plain(amount);

  /// Symbol ready to sit in front of a number ("₱", "Rp ").
  String get moneyPrefix => _watched.prefix;

  /// Bare symbol ("₱", "Rp") — for labels like the Reports sort toggle.
  String get moneySymbol => _watched.symbol;

  /// "0.00" or "0" depending on the currency's decimals.
  String get moneyHint => _watched.zeroHint;

  /// Current currency without subscribing to changes — for callbacks.
  Currency get currencyRead =>
      Provider.of<CurrencyProvider>(this, listen: false).currency;
}
