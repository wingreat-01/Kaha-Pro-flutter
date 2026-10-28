import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// "Keep screen on" for phones/tablets: stops the display from dimming
/// and turning off mid-shift while a cashier is working.
///
/// Only held while someone is logged in (HomeShell calls [setInUse]) —
/// the login and store-setup screens let the device sleep normally, so a
/// register left logged out doesn't burn its screen all night.
///
/// Saved per device via shared_preferences, like ReceiptOptionsProvider —
/// a counter tablet on a charger and a phone in a pocket can differ. On
/// by default, since a POS screen going dark is the common complaint.
class KeepScreenOnProvider extends ChangeNotifier {
  static const _key = 'keep_screen_on';

  /// Android/iOS only. Desktop and web either don't sleep the same way
  /// or the browser decides, so the setting is hidden there.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  bool _enabled = true;
  bool _inUse = false;

  bool get enabled => _enabled;

  /// Register as `KeepScreenOnProvider()..load()` in main.dart.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_key) ?? true;
      if (saved != _enabled) {
        _enabled = saved;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable — stay on the default rather than crash.
    }
    await _apply();
  }

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    await _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Not persisted this time; still applies for the current session.
    }
  }

  /// True while a staff member is logged in (HomeShell mounted).
  Future<void> setInUse(bool value) async {
    _inUse = value;
    await _apply();
  }

  /// Re-asserts the lock — call when the app returns to the foreground,
  /// since some Android builds drop it while the app is in the background.
  Future<void> reapply() => _apply();

  Future<void> _apply() async {
    if (!isSupported) return;
    try {
      await WakelockPlus.toggle(enable: _enabled && _inUse);
    } catch (e) {
      // Never let a wakelock hiccup break the register.
      debugPrint('KeepScreenOnProvider: could not toggle wakelock: $e');
    }
  }
}
