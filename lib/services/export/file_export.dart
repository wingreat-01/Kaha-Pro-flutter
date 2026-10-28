// Compile-time platform switch, same pattern as printing/printer_service.dart:
// dart:io isn't available on web, so the browser download lives in its own
// file. Both expose saveExportFile().
export 'file_export_io.dart' if (dart.library.html) 'file_export_web.dart';
