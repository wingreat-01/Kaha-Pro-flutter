// Compile-time platform switch — no runtime Platform.isX check needed
// or possible, since dart:io itself isn't available on web at all.
// Exports the phone implementation by default; overridden with the
// web implementation when dart:html is available (i.e. building for
// web). Both files expose the same createReceiptPrinterService()
// factory and ReceiptPrinterService-implementing class.
export 'receipt_printer_service_io.dart'
    if (dart.library.html) 'receipt_printer_service_web.dart';
