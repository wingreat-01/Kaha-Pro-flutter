// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// Same dart:html approach as printing/receipt_printer_service_web.dart.
import 'dart:html' as html;
import 'dart:typed_data';

/// Browser: triggers a normal file download. See file_export_io.dart for
/// the return-value contract.
Future<String?> saveExportFile(String filename, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser a moment to start the download before revoking.
  Future<void>.delayed(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(url));
  return 'Downloaded $filename';
}
