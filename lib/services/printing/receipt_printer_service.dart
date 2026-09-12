import '../../models/printer_config.dart';
import '../../models/store.dart';
import '../../models/transaction.dart';

/// Outcome of a print attempt. Kept as a small value type (not a bool)
/// so a failure can carry a message worth showing the cashier —
/// "printer off/out of range" vs "wrong IP" are different fixes.
class PrintResult {
  final bool success;
  final String? error;
  const PrintResult.ok()
      : success = true,
        error = null;
  const PrintResult.failure(this.error) : success = false;
}

/// Platform-agnostic printing contract. `createReceiptPrinterService()`
/// (see printer_service.dart) resolves to the io or web implementation
/// at compile time via conditional export — callers (PrinterProvider)
/// never branch on platform themselves.
abstract class ReceiptPrinterService {
  /// Discover Bluetooth printers already paired with the OS. The web
  /// implementation always returns an empty list — pairing a device
  /// from inside a browser would mean Web Bluetooth, which is
  /// Chromium-only and out of scope for now (see chat notes).
  Future<List<PrinterConfig>> scanBluetoothPrinters();

  /// Sends a short test line to confirm a saved printer actually
  /// works, without needing a real sale.
  Future<PrintResult> testPrint(PrinterConfig config);

  /// Prints a full receipt for [transaction]. [store] supplies the
  /// header/footer fields (name, address, TIN, contact, permit,
  /// receiptFooter) — the same fields ReceiptPreviewScreen already
  /// renders on screen.
  Future<PrintResult> printReceipt({
    required PrinterConfig config,
    required Transaction transaction,
    required Store? store,
  });
}
