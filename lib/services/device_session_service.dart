import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Backs the single-active-device login rule: generates and persists a
/// random id for this install, and wraps the claim_device_session /
/// touch_device_session RPCs (see migration
/// 20260925_020_owner_device_sessions.sql).
///
/// No new pubspec dependency -- reuses shared_preferences, already used
/// by PrinterProvider/CurrencyProvider/ReceiptOptionsProvider/
/// ThemeProvider for the same "small persisted value" purpose.
class DeviceSessionService {
  static const _prefsKey = 'merq_device_id';

  static String? _cachedDeviceId;

  /// Random hex id for this install. Stored once and reused for the
  /// life of the app install -- reinstalling the app generates a new
  /// one (there's no stable hardware id used here on purpose, since
  /// reading one would need extra platform permissions/plugins this
  /// project doesn't otherwise need).
  static Future<String> deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) {
      _cachedDeviceId = existing;
      return existing;
    }

    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_prefsKey, id);
    _cachedDeviceId = id;
    return id;
  }

  /// Attempts to claim the just-signed-in session for this device.
  /// Call right after a successful signInWithPassword()/signUp().
  ///
  /// Returns (allowed: true) if this device now holds the session.
  /// Returns (allowed: false, existingDeviceLabel: ...) if another
  /// device already holds it -- the caller is expected to sign this
  /// session back out immediately, since calling this after
  /// signInWithPassword() already means a valid session exists here.
  static Future<DeviceClaimResult> claim({
    required String deviceLabel,
    bool force = false,
  }) async {
    final id = await deviceId();
    final res = await Supabase.instance.client.rpc('claim_device_session', params: {
      'p_device_id': id,
      'p_device_label': deviceLabel,
      'p_force': force,
    });
    final map = res as Map<String, dynamic>;
    return DeviceClaimResult(
      allowed: map['allowed'] as bool,
      existingDeviceLabel: map['existing_device_label'] as String?,
    );
  }

  /// Heartbeat for the device that currently holds the session --
  /// returns false if another device has since force-claimed it, in
  /// which case the caller should sign out locally (see main.dart).
  /// Swallows errors (offline, etc.) as "still fine" rather than
  /// signing someone out for a network blip.
  static Future<bool> stillClaimed() async {
    try {
      final id = await deviceId();
      final res = await Supabase.instance.client.rpc('touch_device_session', params: {
        'p_device_id': id,
      });
      return res as bool;
    } catch (_) {
      return true;
    }
  }
}

class DeviceClaimResult {
  final bool allowed;
  final String? existingDeviceLabel;
  DeviceClaimResult({required this.allowed, this.existingDeviceLabel});
}
