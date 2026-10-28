import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands an exported file to the user. Returns a message for a snackbar,
/// or null when the system share sheet already gave its own feedback.
///
/// Phones/tablets: share sheet (Save to Files/Drive, email, Messenger,
/// Viber...). Desktop apps: written straight to Downloads — the share
/// sheet there can't attach files.
Future<String?> saveExportFile(String filename, Uint8List bytes) async {
  final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  if (mobile) {
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/$filename').writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: filename);
    return null;
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = await File('${dir.path}${Platform.pathSeparator}$filename').writeAsBytes(bytes, flush: true);
  return 'Saved to ${file.path}';
}
