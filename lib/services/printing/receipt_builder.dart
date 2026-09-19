import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../models/store.dart';
import '../../models/transaction.dart';
import '../../models/vat_breakdown.dart';
import '../../state/currency_provider.dart';
import '../../state/receipt_options_provider.dart';

/// Builds the raw ESC/POS byte stream for a receipt — used by both
/// the Bluetooth and network (socket) paths in
/// receipt_printer_service_io.dart, since both just want the same
/// bytes sent over a different transport. Layout deliberately mirrors
/// ReceiptPreviewScreen's on-screen `_ReceiptTicket` (same sections,
/// same order) so what a cashier sees in preview matches what prints.
class EscPosReceiptBuilder {
  static Future<List<int>> build(Transaction transaction, Store? store) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];

    // ── Store header ──
    bytes.addAll(generator.text(
      store?.name ?? 'Store',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    if ((store?.address ?? '').isNotEmpty) {
      bytes.addAll(generator.text(store!.address!, styles: const PosStyles(align: PosAlign.center)));
    }
    if ((store?.contactNumber ?? '').isNotEmpty) {
      bytes.addAll(generator.text(store!.contactNumber!, styles: const PosStyles(align: PosAlign.center)));
    }
    if ((store?.tin ?? '').isNotEmpty) {
      bytes.addAll(generator.text('TIN: ${store!.tin!}', styles: const PosStyles(align: PosAlign.center)));
    }
    if ((store?.permitNumber ?? '').isNotEmpty) {
      bytes.addAll(generator.text(store!.permitNumber!, styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(generator.hr());

    // ── Transaction meta ──
    bytes.addAll(generator.row([
      PosColumn(text: 'Receipt #', width: 6),
      PosColumn(text: transaction.transactionNumber, width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(generator.row([
      PosColumn(text: 'Date', width: 6),
      PosColumn(text: _formatDateTime(transaction.timestamp), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]));
    if ((transaction.cashierName ?? '').isNotEmpty) {
      bytes.addAll(generator.row([
        PosColumn(text: 'Cashier', width: 6),
        PosColumn(text: transaction.cashierName!, width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]));
    }
    bytes.addAll(generator.hr());

    // ── Line items ──
    for (final item in transaction.items) {
      bytes.addAll(generator.text(item.name, styles: const PosStyles(bold: true)));
      bytes.addAll(generator.row([
        PosColumn(text: '${item.quantity} x ${CurrencyProvider.active.plain(item.price)}', width: 6),
        PosColumn(text: CurrencyProvider.active.plain(item.lineTotal), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]));
    }
    bytes.addAll(generator.hr());

    // ── Totals / VAT / discount breakdown ── (mirrors ReceiptPreviewScreen)
    final showVat = ReceiptOptionsProvider.vatBreakdownActive;
    final vat = VatBreakdown.fromTransaction(transaction, decimals: CurrencyProvider.active.decimals);
    final discountLabel = '20% ${transaction.discountType == 'senior' ? 'Senior' : 'PWD'} Discount';
    if (showVat) {
      bytes.addAll(_amountRow(generator, 'VATable Sales', vat.vatableSales));
      if (transaction.hasDiscount) {
        bytes.addAll(_amountRow(generator, 'VAT-Exempt Sales', vat.vatExemptSales));
      }
      bytes.addAll(_amountRow(generator, 'VAT (12%)', vat.vatAmount));
      if (transaction.hasDiscount) {
        bytes.addAll(_amountRow(generator, discountLabel, -transaction.discountAmount));
      }
    } else if (transaction.hasDiscount) {
      final subtotal = transaction.total + transaction.discountAmount + transaction.vatExemptAmount;
      bytes.addAll(_amountRow(generator, 'Subtotal', subtotal));
      bytes.addAll(_amountRow(generator, 'Less VAT', -transaction.vatExemptAmount));
      bytes.addAll(_amountRow(generator, discountLabel, -transaction.discountAmount));
    }
    bytes.addAll(_amountRow(generator, showVat ? 'AMOUNT DUE' : 'TOTAL', transaction.total, bold: true));
    bytes.addAll(_amountRow(generator, transaction.paymentMethodName ?? 'Payment', transaction.cashTendered));
    if (transaction.change > 0) {
      bytes.addAll(_amountRow(generator, 'Change', transaction.change));
    }

    if (transaction.hasDiscount) {
      bytes.addAll(generator.hr());
      final label = transaction.discountType == 'senior' ? 'Senior Citizen' : 'PWD';
      bytes.addAll(generator.text('$label: ${transaction.discountHolderName ?? ''}'));
      if ((transaction.discountIdNumber ?? '').isNotEmpty) {
        bytes.addAll(generator.text('ID No: ${transaction.discountIdNumber!}'));
      }
    }

    if ((store?.receiptFooter ?? '').isNotEmpty) {
      bytes.addAll(generator.hr());
      bytes.addAll(generator.text(store!.receiptFooter!, styles: const PosStyles(align: PosAlign.center)));
    }

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  /// Minimal test line — reuses the same Generator plumbing as a real
  /// receipt, so a successful test genuinely proves the print path
  /// works end to end, not just that the connection opened.
  static Future<List<int>> buildTestLine() async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];
    bytes.addAll(generator.text('MERQ TEST PRINT', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.text(DateTime.now().toString(), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  static List<int> _amountRow(Generator generator, String label, double value, {bool bold = false}) {
    final text = CurrencyProvider.active.plain(value);
    return generator.row([
      PosColumn(text: label, width: 6, styles: PosStyles(bold: bold)),
      PosColumn(text: text, width: 6, styles: PosStyles(align: PosAlign.right, bold: bold)),
    ]);
  }

  static String _formatDateTime(DateTime dt) {
    final h24 = dt.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final ampm = h24 < 12 ? 'AM' : 'PM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '$h12:$mm $ampm';
  }
}
