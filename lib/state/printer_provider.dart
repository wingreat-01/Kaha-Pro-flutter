import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_config.dart';
import '../models/store.dart';
import '../models/transaction.dart';
import '../services/printing/printer_service.dart';
import '../services/printing/receipt_printer_service.dart';

enum PrinterConnectionStatus { idle, printing, error }

/// Owns the saved printer config and drives the actual print action
/// through whichever ReceiptPrinterService this platform resolves to
/// (see printer_service.dart's conditional export). The config is
/// persisted per-device via shared_preferences, deliberately not
/// synced through Supabase — which printer a register is wired to is
/// a property of that physical device/tablet, not the store, so a
/// second device shouldn't inherit or overwrite the first one's
/// printer.
class PrinterProvider extends ChangeNotifier {
  static const _prefsKey = 'kahapro_saved_printer';

  final ReceiptPrinterService _service = createReceiptPrinterService();

  PrinterConfig? _savedPrinter;
  PrinterConnectionStatus _status = PrinterConnectionStatus.idle;
  String? _lastError;

  PrinterConfig? get savedPrinter => _savedPrinter;
  bool get hasPrinter => _savedPrinter != null;
  PrinterConnectionStatus get status => _status;
  String? get lastError => _lastError;

  /// Call once at app start (see main.dart) to restore whatever
  /// printer was saved on this device previously.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      _savedPrinter = PrinterConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    }
  }

  Future<void> savePrinter(PrinterConfig config) async {
    _savedPrinter = config;
    _lastError = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<void> clearPrinter() async {
    _savedPrinter = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<List<PrinterConfig>> scanBluetoothPrinters() => _service.scanBluetoothPrinters();

  Future<bool> testPrint(PrinterConfig config) async {
    _status = PrinterConnectionStatus.printing;
    _lastError = null;
    notifyListeners();
    final result = await _service.testPrint(config);
    _status = result.success ? PrinterConnectionStatus.idle : PrinterConnectionStatus.error;
    _lastError = result.error;
    notifyListeners();
    return result.success;
  }

  /// Prints using the saved printer. Returns false (with lastError
  /// set) if nothing's configured yet — ReceiptPreviewScreen routes to
  /// Settings in that case rather than failing silently.
  Future<bool> printReceipt({required Transaction transaction, required Store? store}) async {
    final config = _savedPrinter;
    if (config == null) {
      _lastError = 'No printer set up yet — add one in Settings.';
      notifyListeners();
      return false;
    }
    _status = PrinterConnectionStatus.printing;
    _lastError = null;
    notifyListeners();
    final result = await _service.printReceipt(config: config, transaction: transaction, store: store);
    _status = result.success ? PrinterConnectionStatus.idle : PrinterConnectionStatus.error;
    _lastError = result.error;
    notifyListeners();
    return result.success;
  }
}
