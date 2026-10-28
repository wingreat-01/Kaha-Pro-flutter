import 'dart:typed_data';
import '../../models/employee.dart';
import '../../models/ingredient.dart';
import '../../models/product.dart';
import '../../models/transaction.dart';
import 'csv.dart';

/// One exportable file: name + CSV bytes.
class ExportFile {
  final String filename;
  final Uint8List bytes;
  final int rowCount;
  const ExportFile(this.filename, this.bytes, this.rowCount);
}

String _range(DateTime from, DateTime to) => '${csvDate(from)}_to_${csvDate(to)}';

bool _inRange(DateTime t, DateTime from, DateTime to) {
  final day = DateTime(t.year, t.month, t.day);
  return !day.isBefore(DateTime(from.year, from.month, from.day)) &&
      !day.isAfter(DateTime(to.year, to.month, to.day));
}

String _status(Transaction t) => t.isVoided ? 'Voided' : t.isPending ? 'Pending sync' : 'Completed';

/// One row per sale. Voided sales are included (marked) so the file
/// reconciles with the Transactions list; filter the Status column to
/// leave them out of totals.
ExportFile salesTransactionsExport(List<Transaction> all, DateTime from, DateTime to) {
  final rows = all
      .where((t) => _inRange(t.timestamp, from, to))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return ExportFile(
    'merq-sales-${_range(from, to)}.csv',
    buildCsv(
      [
        'Date', 'Time', 'Sale #', 'Status', 'Cashier', 'Payment method', 'Items',
        'Discount type', 'Discount amount', 'VAT exempt', 'Total', 'Cash tendered', 'Change',
        'Voided by', 'Void reason',
      ],
      rows.map((t) => [
            csvDate(t.timestamp),
            csvTime(t.timestamp),
            t.transactionNumber,
            _status(t),
            t.cashierName,
            t.paymentMethodName,
            t.itemCount,
            t.discountType == 'senior' ? 'Senior' : t.discountType == 'pwd' ? 'PWD' : null,
            csvMoney(t.discountAmount),
            csvMoney(t.vatExemptAmount),
            csvMoney(t.total),
            csvMoney(t.cashTendered),
            csvMoney(t.change),
            t.voidedByName,
            t.voidReason,
          ]),
    ),
    rows.length,
  );
}

/// One row per line item — for "what sold" analysis in a spreadsheet
/// (pivot by product, category, day...).
ExportFile salesItemsExport(List<Transaction> all, DateTime from, DateTime to) {
  final sales = all
      .where((t) => _inRange(t.timestamp, from, to))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final rows = <List<Object?>>[
    for (final t in sales)
      for (final i in t.items)
        [
          csvDate(t.timestamp),
          csvTime(t.timestamp),
          t.transactionNumber,
          _status(t),
          i.name,
          i.variantName,
          i.category,
          i.quantity,
          csvMoney(i.price),
          csvMoney(i.lineTotal),
          t.cashierName,
        ],
  ];
  return ExportFile(
    'merq-items-sold-${_range(from, to)}.csv',
    buildCsv(
      ['Date', 'Time', 'Sale #', 'Status', 'Item', 'Size', 'Category', 'Qty', 'Unit price', 'Line total', 'Cashier'],
      rows,
    ),
    rows.length,
  );
}

/// Current stock of every product, one row per size when a size keeps its
/// own count. Stock value uses the product's cost per unit when set.
ExportFile productStockExport(List<Product> products, DateTime asOf) {
  final sorted = [...products]..sort((a, b) {
      final c = a.category.compareTo(b.category);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  final rows = <List<Object?>>[];
  for (final p in sorted) {
    final sized = p.variants.where((v) => v.stockQty != null).toList();
    if (p.trackStock && sized.isNotEmpty) {
      for (final v in sized) {
        rows.add(_productRow(p, size: v.name, price: v.price, qty: v.stockQty!));
      }
    } else {
      rows.add(_productRow(p, price: p.price, qty: p.trackStock ? p.stockQty : null));
    }
  }
  return ExportFile(
    'merq-product-stock-${csvDate(asOf)}.csv',
    buildCsv(
      [
        'Category', 'Product', 'Size', 'Barcode', 'Track stock', 'Stock qty', 'Unit',
        'Low stock at', 'Low stock?', 'Price', 'Cost per unit', 'Stock value (cost)',
      ],
      rows,
    ),
    rows.length,
  );
}

List<Object?> _productRow(Product p, {String? size, required double price, int? qty}) {
  final cost = p.costPerUnit;
  return [
    p.category,
    p.name,
    size,
    p.barcode,
    p.trackStock ? 'Yes' : 'No',
    qty,
    p.trackStock ? p.unitDisplay : null,
    p.trackStock ? p.lowStockThreshold : null,
    qty == null ? null : (qty <= p.lowStockThreshold ? 'Yes' : 'No'),
    csvMoney(price),
    cost == null ? null : csvMoney(cost),
    (cost == null || qty == null) ? null : csvMoney(cost * qty),
  ];
}

ExportFile ingredientStockExport(List<Ingredient> ingredients, DateTime asOf) {
  final sorted = [...ingredients]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return ExportFile(
    'merq-ingredient-stock-${csvDate(asOf)}.csv',
    buildCsv(
      ['Ingredient', 'Stock qty', 'Unit', 'Low stock at', 'Low stock?', 'Cost per unit', 'Stock value (cost)'],
      sorted.map((i) => [
            i.name,
            i.stockQuantity,
            i.unitDisplay,
            i.lowStockThreshold,
            i.isLowStock ? 'Yes' : 'No',
            i.costPerUnit == null ? null : csvMoney(i.costPerUnit!),
            i.costPerUnit == null ? null : csvMoney(i.costPerUnit! * i.stockQuantity),
          ]),
    ),
    sorted.length,
  );
}

/// Punches in a range, oldest first. Photos aren't included — only
/// whether one was taken.
ExportFile timeRecordsExport(
  List<TimeEntry> entries,
  Map<String, String> employeeNames,
  DateTime from,
  DateTime to,
) {
  final rows = entries.where((e) => _inRange(e.clockIn, from, to)).toList()
    ..sort((a, b) => a.clockIn.compareTo(b.clockIn));
  return ExportFile(
    'merq-time-records-${_range(from, to)}.csv',
    buildCsv(
      [
        'Employee', 'Date', 'Time in', 'Date out', 'Time out', 'Hours', 'Source',
        'Needs review', 'Note', 'Edited by',
      ],
      rows.map((e) => [
            employeeNames[e.employeeId] ?? 'Removed employee',
            csvDate(e.clockIn),
            csvTime(e.clockIn),
            e.clockOut == null ? null : csvDate(e.clockOut!),
            e.clockOut == null ? 'Still in' : csvTime(e.clockOut!),
            e.clockOut == null ? null : (e.workedMinutes / 60).toStringAsFixed(2),
            e.source == 'manual' ? 'Manual' : 'Time clock',
            e.needsReview ? 'Yes' : 'No',
            e.note,
            e.editedBy,
          ]),
    ),
    rows.length,
  );
}

/// A saved payroll run, one row per employee. Manual adjustments are
/// listed in two text columns so the totals columns stay numeric.
ExportFile payrollRunExport(PayrollRun run, List<PayrollLine> lines) {
  String list(Iterable<PayAdjustment> items) =>
      items.map((a) => '${a.label} ${csvMoney(a.amount)}').join('; ');
  return ExportFile(
    'merq-payroll-${_range(run.periodStart, run.periodEnd)}.csv',
    buildCsv(
      [
        'Employee', 'Period start', 'Period end', 'Daily rate', 'Days worked', 'Basic pay',
        'Overtime (min)', 'Overtime pay', 'Additions', 'Additions detail', 'Gross pay',
        'Late (min)', 'Late deduction', 'Undertime (min)', 'Undertime deduction',
        'Other deductions', 'Deductions detail', 'Total deductions', 'Net pay',
      ],
      lines.map((l) => [
            l.employeeName,
            csvDate(run.periodStart),
            csvDate(run.periodEnd),
            csvMoney(l.dailyRate),
            l.daysWorked,
            csvMoney(l.basicPay),
            l.overtimeMinutes,
            csvMoney(l.overtimePay),
            csvMoney(l.additions),
            list(l.adjustments.where((a) => !a.isDeduction)),
            csvMoney(l.grossPay),
            l.lateMinutes,
            csvMoney(l.lateDeduction),
            l.undertimeMinutes,
            csvMoney(l.undertimeDeduction),
            csvMoney(l.otherDeductions),
            list(l.adjustments.where((a) => a.isDeduction)),
            csvMoney(l.totalDeductions),
            csvMoney(l.netPay),
          ]),
    ),
    lines.length,
  );
}
