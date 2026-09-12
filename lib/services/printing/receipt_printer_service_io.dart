import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../models/printer_config.dart';
import '../../models/store.dart';
import '../../models/transaction.dart';
import 'receipt_builder.dart';
import 'receipt_printer_service.dart';

/// Phone implementation. Bluetooth goes over classic RFCOMM via
/// print_bluetooth_thermal — this only works with printers that
/// support classic Bluetooth SPP. iOS in particular restricts
/// non-MFi-certified classic Bluetooth accessories, so a Bluetooth
/// thermal printer that pairs and prints fine on Android may refuse
/// to connect at all on iOS — that's an iOS platform restriction, not
/// a bug in this code. Network printers (WiFi, raw TCP to port 9100)
/// don't have that problem and are the more reliable cross-platform
/// path; recommend those to iOS-heavy customers.
class IoReceiptPrinterService implements ReceiptPrinterService {
  @override
  Future<List<PrinterConfig>> scanBluetoothPrinters() async {
    // Android 12+ requires runtime BLUETOOTH_CONNECT/BLUETOOTH_SCAN
    // grants before any classic-Bluetooth call will return real data
    // (silently empty otherwise, not an error) — request them here
    // rather than assuming AndroidManifest.xml's declaration alone is
    // enough.
    final statuses = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      return [];
    }

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) return [];

    final paired = await PrintBluetoothThermal.pairedBluetooths;
    return paired
        .map((d) => PrinterConfig(
              type: PrinterConnectionType.bluetooth,
              name: d.name,
              address: d.macAdress,
            ))
        .toList();
  }

  @override
  Future<PrintResult> testPrint(PrinterConfig config) async {
    final bytes = await EscPosReceiptBuilder.buildTestLine();
    return _send(config, bytes);
  }

  @override
  Future<PrintResult> printReceipt({
    required PrinterConfig config,
    required Transaction transaction,
    required Store? store,
  }) async {
    try {
      final bytes = await EscPosReceiptBuilder.build(transaction, store);
      return _send(config, bytes);
    } catch (e) {
      return PrintResult.failure('Could not build the receipt: $e');
    }
  }

  Future<PrintResult> _send(PrinterConfig config, List<int> bytes) {
    return config.type == PrinterConnectionType.bluetooth
        ? _sendBluetooth(config, bytes)
        : _sendNetwork(config, bytes);
  }

  Future<PrintResult> _sendBluetooth(PrinterConfig config, List<int> bytes) async {
    try {
      final connected = await PrintBluetoothThermal.connect(macPrinterAddress: config.address);
      if (!connected) {
        return const PrintResult.failure('Could not connect to the Bluetooth printer — make sure it\'s on and in range.');
      }
      final wrote = await PrintBluetoothThermal.writeBytes(bytes);
      await PrintBluetoothThermal.disconnect;
      return wrote
          ? const PrintResult.ok()
          : const PrintResult.failure('Printer did not accept the print job.');
    } catch (e) {
      return PrintResult.failure('Bluetooth print failed: $e');
    }
  }

  Future<PrintResult> _sendNetwork(PrinterConfig config, List<int> bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(config.address, config.port, timeout: const Duration(seconds: 5));
      socket.add(bytes);
      await socket.flush();
      return const PrintResult.ok();
    } catch (e) {
      return PrintResult.failure(
          'Could not reach the printer at ${config.address}:${config.port} — check it\'s powered on and on the same WiFi network.');
    } finally {
      socket?.destroy();
    }
  }
}

ReceiptPrinterService createReceiptPrinterService() => IoReceiptPrinterService();
