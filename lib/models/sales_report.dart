/// One row in the best-sellers list — a product (or a specific size of
/// one, e.g. "Coffee (Large)") aggregated across every transaction in
/// the report's date range.
class ProductSalesLine {
  final String productId;
  final String? variantId;
  final String displayName; // already includes size, e.g. "Coffee (Large)"
  final int quantitySold;
  final double revenue;

  const ProductSalesLine({
    required this.productId,
    this.variantId,
    required this.displayName,
    required this.quantitySold,
    required this.revenue,
  });
}

/// One row in the cashier breakdown — every transaction in the range
/// grouped by who rang it up.
class CashierSalesLine {
  final String cashierName; // "Unknown" for older rows recorded before
                             // cashier tracking existed
  final int transactionCount;
  final double revenue;

  const CashierSalesLine({
    required this.cashierName,
    required this.transactionCount,
    required this.revenue,
  });
}

/// Everything the Reports screen needs for one date range, computed
/// once so the screen itself never touches raw Transaction lists.
class SalesReport {
  final DateTime rangeStart;
  final DateTime rangeEnd; // inclusive, end-of-day
  final double totalRevenue;
  final double cashIn; // == totalRevenue today (all sales are cash),
                        // kept as a separate field so a future
                        // non-cash tender type doesn't require a
                        // screen change
  final int transactionCount;
  final int itemsSold;
  final List<ProductSalesLine> productBreakdown; // unsorted; screen sorts by qty or revenue
  final List<CashierSalesLine> cashierBreakdown; // sorted by revenue desc

  const SalesReport({
    required this.rangeStart,
    required this.rangeEnd,
    required this.totalRevenue,
    required this.cashIn,
    required this.transactionCount,
    required this.itemsSold,
    required this.productBreakdown,
    required this.cashierBreakdown,
  });

  double get avgTransactionValue => transactionCount == 0 ? 0 : totalRevenue / transactionCount;

  factory SalesReport.empty(DateTime start, DateTime end) => SalesReport(
        rangeStart: start,
        rangeEnd: end,
        totalRevenue: 0,
        cashIn: 0,
        transactionCount: 0,
        itemsSold: 0,
        productBreakdown: const [],
        cashierBreakdown: const [],
      );
}

/// Quick date-range presets for the chip row. `custom` means the owner
/// picked an explicit range via the date picker instead of a chip.
enum DateRangePreset { today, yesterday, thisWeek, thisMonth, custom }
