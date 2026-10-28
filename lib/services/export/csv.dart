import 'dart:convert';
import 'dart:typed_data';

/// Builds a CSV file (RFC 4180) as UTF-8 bytes with a byte-order mark, so
/// Excel shows ₱, ñ and other non-ASCII text correctly instead of
/// guessing the wrong encoding.
///
/// Cells: null → empty, num/bool → as-is, everything else → toString().
///
/// Text that starts with = + - @ (or a tab/CR) is prefixed with a quote
/// so a spreadsheet shows it as text instead of running it as a formula —
/// product, employee and note text are typed in by users, and a value
/// like `=HYPERLINK(...)` would otherwise execute when the file is opened.
/// Plain numbers ("-12.50") are left alone.
Uint8List buildCsv(List<String> header, Iterable<List<Object?>> rows) {
  final out = StringBuffer('﻿');
  out.write(_line(header));
  for (final row in rows) {
    out.write(_line(row));
  }
  return Uint8List.fromList(utf8.encode(out.toString()));
}

String _line(List<Object?> cells) => '${cells.map(_cell).join(',')}\r\n';

String _cell(Object? value) {
  if (value == null) return '';
  if (value is num || value is bool) return value.toString();
  var text = value.toString();
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0]) && double.tryParse(text) == null) {
    text = "'$text";
  }
  if (text.contains(RegExp(r'[",\r\n]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// Money as a fixed 2-decimal string ("1250.00") — avoids 1250.4999999.
String csvMoney(double value) => value.toStringAsFixed(2);

/// 2026-10-28
String csvDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 14:05 (24-hour, so spreadsheets sort and parse it)
String csvTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
