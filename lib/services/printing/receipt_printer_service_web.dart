import 'dart:html' as html;
import '../../models/printer_config.dart';
import '../../models/store.dart';
import '../../models/transaction.dart';
import '../../state/currency_provider.dart';
import 'receipt_printer_service.dart';

/// Web implementation. Browsers don't expose raw Bluetooth RFCOMM or
/// TCP sockets, so "printing" here means handing a receipt-shaped
/// HTML document to the browser's own print dialog — the customer
/// picks whatever printer (Bluetooth or WiFi, doesn't matter) is
/// already set up as an OS printer on that computer/tablet. The saved
/// PrinterConfig is accepted for interface parity with the phone
/// implementation but isn't actually used to address a device here —
/// on web, PrinterProvider.hasPrinter just gates whether the "Print"
/// button shows "no printer configured yet" instead.
class WebReceiptPrinterService implements ReceiptPrinterService {
  @override
  Future<List<PrinterConfig>> scanBluetoothPrinters() async => [];

  @override
  Future<PrintResult> testPrint(PrinterConfig config) async {
    _printHtml('<div class="center bold">MERQ TEST PRINT</div><div class="center">${DateTime.now()}</div>');
    return const PrintResult.ok();
  }

  @override
  Future<PrintResult> printReceipt({
    required PrinterConfig config,
    required Transaction transaction,
    required Store? store,
  }) async {
    try {
      _printHtml(_buildHtml(transaction, store));
      return const PrintResult.ok();
    } catch (e) {
      return PrintResult.failure('Could not open the print dialog: $e');
    }
  }

  void _printHtml(String bodyHtml) {
    // Printed via a hidden same-origin iframe rather than calling
    // window.print() on the app's own window — that would print the
    // whole Flutter canvas around the receipt. The iframe holds only
    // the receipt markup, so the print dialog/printed page shows just
    // the ticket.
    //
    // Content is set via `srcdoc` rather than
    // document.open()/writeln()/close() — dart:html's typing of
    // Window.document/Document/HtmlDocument doesn't cleanly expose
    // those methods through a contentWindow cast, whereas srcdoc is a
    // plain string setter with no such friction.
    final iframe = html.IFrameElement()
      ..style.position = 'fixed'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.width = '0'
      ..style.height = '0'
      ..style.border = 'none';

    final fullHtml = '''
      <html><head><title>Receipt</title>
      <style>
        @page { size: 58mm auto; margin: 0; }
        body { font-family: "Courier New", monospace; font-size: 11px; width: 58mm; margin: 0; padding: 8px; color: #000; }
        .center { text-align: center; }
        .row { display: flex; justify-content: space-between; }
        .bold { font-weight: 700; }
        hr { border: none; border-top: 1px dashed #000; margin: 6px 0; }
      </style>
      </head><body>$bodyHtml</body></html>
    ''';

    // Print only once the iframe has actually finished loading the
    // srcdoc content — printing immediately after append() can race
    // ahead of layout and print a blank page.
    iframe.onLoad.first.then((_) {
      final win = iframe.contentWindow as html.Window;
      win.print();
      Future.delayed(const Duration(seconds: 1), () => iframe.remove());
    });

    iframe.srcdoc = fullHtml;
    html.document.body!.append(iframe);
  }

  String _buildHtml(Transaction transaction, Store? store) {
    final b = StringBuffer();
    b.writeln('<div class="center bold" style="font-size:14px;">${store?.name ?? 'Store'}</div>');
    if ((store?.address ?? '').isNotEmpty) b.writeln('<div class="center">${store!.address}</div>');
    if ((store?.contactNumber ?? '').isNotEmpty) b.writeln('<div class="center">${store!.contactNumber}</div>');
    if ((store?.tin ?? '').isNotEmpty) b.writeln('<div class="center">TIN: ${store!.tin}</div>');
    if ((store?.permitNumber ?? '').isNotEmpty) b.writeln('<div class="center">${store!.permitNumber}</div>');
    b.writeln('<hr>');
    b.writeln('<div class="row"><span>Receipt #</span><span>${transaction.transactionNumber}</span></div>');
    b.writeln('<div class="row"><span>Date</span><span>${_formatDateTime(transaction.timestamp)}</span></div>');
    if ((transaction.cashierName ?? '').isNotEmpty) {
      b.writeln('<div class="row"><span>Cashier</span><span>${transaction.cashierName}</span></div>');
    }
    b.writeln('<hr>');
    for (final item in transaction.items) {
      b.writeln('<div class="bold">${item.name}</div>');
      b.writeln(
          '<div class="row"><span>${item.quantity} x ${CurrencyProvider.active.plain(item.price)}</span><span>${CurrencyProvider.active.plain(item.lineTotal)}</span></div>');
    }
    b.writeln('<hr>');
    if (transaction.hasDiscount) {
      final subtotal = transaction.total + transaction.discountAmount + transaction.vatExemptAmount;
      b.writeln(_amountRow('Subtotal', subtotal));
      b.writeln(_amountRow('Less VAT', -transaction.vatExemptAmount));
      b.writeln(_amountRow(
          '20% ${transaction.discountType == 'senior' ? 'Senior' : 'PWD'} Discount', -transaction.discountAmount));
    }
    b.writeln(_amountRow('TOTAL', transaction.total, bold: true));
    b.writeln(_amountRow(transaction.paymentMethodName ?? 'Payment', transaction.cashTendered));
    if (transaction.change > 0) b.writeln(_amountRow('Change', transaction.change));
    if (transaction.hasDiscount) {
      b.writeln('<hr>');
      final label = transaction.discountType == 'senior' ? 'Senior Citizen' : 'PWD';
      b.writeln('<div>$label: ${transaction.discountHolderName ?? ''}</div>');
      if ((transaction.discountIdNumber ?? '').isNotEmpty) {
        b.writeln('<div>ID No: ${transaction.discountIdNumber}</div>');
      }
    }
    if ((store?.receiptFooter ?? '').isNotEmpty) {
      b.writeln('<hr>');
      b.writeln('<div class="center">${store!.receiptFooter}</div>');
    }
    return b.toString();
  }

  String _amountRow(String label, double value, {bool bold = false}) {
    final text = CurrencyProvider.active.plain(value);
    final cls = bold ? 'row bold' : 'row';
    return '<div class="$cls"><span>$label</span><span>$text</span></div>';
  }

  String _formatDateTime(DateTime dt) {
    final h24 = dt.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final ampm = h24 < 12 ? 'AM' : 'PM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '$h12:$mm $ampm';
  }
}

ReceiptPrinterService createReceiptPrinterService() => WebReceiptPrinterService();
