import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kahapro_flutter/models/employee.dart';
import 'package:kahapro_flutter/models/product.dart';
import 'package:kahapro_flutter/models/transaction.dart';
import 'package:kahapro_flutter/services/export/csv.dart';
import 'package:kahapro_flutter/services/export/data_exports.dart';

/// Decoded CSV lines, BOM stripped.
List<String> lines(List<int> bytes) {
  // Checked on the raw bytes: Dart's utf8.decode drops a leading BOM.
  expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'Excel needs the BOM for ₱ / ñ');
  return utf8.decode(bytes.sublist(3)).split('\r\n')..removeLast();
}

Transaction sale(String number, DateTime at, double total, {DateTime? voidedAt}) => Transaction(
      id: number,
      transactionNumber: number,
      timestamp: at,
      items: const [TransactionLineItem(productId: 'p1', name: 'Coke', price: 25, quantity: 2, category: 'Drinks')],
      total: total,
      cashTendered: 100,
      change: 100 - total,
      cashierName: 'Maria',
      voidedAt: voidedAt,
      voidedByName: voidedAt == null ? null : 'Owner',
      voidReason: voidedAt == null ? null : 'Wrong item',
    );

void main() {
  group('buildCsv', () {
    test('quotes commas, quotes and newlines; keeps ₱ and ñ', () {
      final out = lines(buildCsv(['A', 'B'], [
        ['Kape, hot', 'He said "hi"'],
        ['line1\nline2', 'Piña ₱50'],
      ]));
      expect(out[1], '"Kape, hot","He said ""hi"""');
      expect(out[2], '"line1\nline2",Piña ₱50');
    });

    test('neutralises formula injection but leaves real numbers alone', () {
      final out = lines(buildCsv(['A', 'B', 'C', 'D'], [
        ['=HYPERLINK("http://x")', '+1+1', '-12.50', '@SUM(A1)'],
      ]));
      expect(out[1], '"\'=HYPERLINK(""http://x"")",\'+1+1,-12.50,\'@SUM(A1)');
    });

    test('null is an empty cell, numbers are written as-is', () {
      expect(lines(buildCsv(['A', 'B', 'C'], [[null, 3, 2.5]]))[1], ',3,2.5');
    });
  });

  test('sales export keeps the date range, sorts oldest first, marks voids', () {
    final file = salesTransactionsExport(
      [
        sale('#00003', DateTime(2026, 10, 2, 9, 0), 50, voidedAt: DateTime(2026, 10, 2, 10)),
        sale('#00001', DateTime(2026, 10, 1, 8, 30), 50),
        sale('#00009', DateTime(2026, 11, 1, 8, 0), 50), // outside range
      ],
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 31),
    );
    expect(file.filename, 'merq-sales-2026-10-01_to_2026-10-31.csv');
    expect(file.rowCount, 2);
    final out = lines(file.bytes);
    expect(out[1], startsWith('2026-10-01,08:30,#00001,Completed,Maria'));
    expect(out[2], contains('Voided'));
    expect(out[2], endsWith('Owner,Wrong item'));
  });

  test('items export has one row per line item', () {
    final file = salesItemsExport([sale('#00001', DateTime(2026, 10, 1, 8, 30), 50)], DateTime(2026, 10, 1), DateTime(2026, 10, 1));
    expect(file.rowCount, 1);
    expect(lines(file.bytes)[1], '2026-10-01,08:30,#00001,Completed,Coke,,Drinks,2,25.00,50.00,Maria');
  });

  test('product stock: untracked products have no qty; value uses cost', () {
    final file = productStockExport(const [
      Product(id: 'a', name: 'Rice meal', price: 99, category: 'Meals'),
      Product(id: 'b', name: 'Coke', price: 25, category: 'Drinks', trackStock: true, stockQty: 3, lowStockThreshold: 5, costPerUnit: 18),
    ], DateTime(2026, 10, 28));
    final out = lines(file.bytes);
    expect(out[1], startsWith('Drinks,Coke,,,Yes,3,'));
    expect(out[1], endsWith(',5,Yes,25.00,18.00,54.00'));
    expect(out[2], 'Meals,Rice meal,,,No,,,,,99.00,,');
  });

  test('payroll export lists adjustments and keeps totals numeric', () {
    final run = PayrollRun(
      id: 'r', periodStart: DateTime(2026, 10, 1), periodEnd: DateTime(2026, 10, 15),
      overtimePaid: false, totalNet: 380, createdAt: DateTime(2026, 10, 16),
    );
    const line = PayrollLine(
      employeeName: 'Juan', dailyRate: 480, daysWorked: 1, lateMinutes: 0, undertimeMinutes: 0,
      overtimeMinutes: 0, basicPay: 480, overtimePay: 0, lateDeduction: 0, undertimeDeduction: 0,
      adjustments: [
        PayAdjustment(label: 'Allowance', amount: 100, isDeduction: false),
        PayAdjustment(label: 'Cash advance', amount: 200, isDeduction: true),
      ],
    );
    final out = lines(payrollRunExport(run, [line]).bytes);
    expect(out[1], 'Juan,2026-10-01,2026-10-15,480.00,1,480.00,0,0.00,100.00,Allowance 100.00,580.00,'
        '0,0.00,0,0.00,200.00,Cash advance 200.00,200.00,380.00');
  });
}
