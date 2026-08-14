/// One row in the best-sellers list — a product (or a specific size of
/// one, e.g. "Coffee (Large)") aggregated across every transaction in
/// the report's date range.
class ProductSalesLine {
  final String productId;
  final String? variantId;
  final String displayName; // already includes size, e.g. "Coffee (Large)"
  final int quantitySold;
  final double revenue;

  /// Total cost of goods for this line's quantitySold, based on the
  /// product's recipe (ingredient quantities × cost_per_unit) at the
  /// time the report was built — not a snapshot from the actual sale,
  /// since transaction_line_items doesn't store one. Null means it
  /// couldn't be computed: the product has no recipe at all, or at
  /// least one ingredient in its recipe has no cost_per_unit set.
  /// Never treated as ₱0 in that case — see SalesReport.grossProfit.
  final double? cost;

  const ProductSalesLine({
    required this.productId,
    this.variantId,
    required this.displayName,
    required this.quantitySold,
    required this.revenue,
    this.cost,
  });

  double? get profit => cost == null ? null : revenue - cost!;
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

  /// Sum of every line's known cost — lines with cost == null (no
  /// recipe, or an ingredient missing a cost) contribute nothing here
  /// rather than being treated as ₱0, so this never understates cost.
  double get totalCost =>
      productBreakdown.fold(0.0, (sum, p) => sum + (p.cost ?? 0));

  /// Revenue minus known cost. Only as complete as [costCoverage]
  /// says it is — see that getter before treating this as exact.
  double get grossProfit => totalRevenue - totalCost;

  /// Fraction of *revenue* (not line count) backed by known cost
  /// data. Weighted by revenue rather than by number of products,
  /// since one high-revenue item with no recipe skews the true
  /// number far more than several small uncosted ones — a raw
  /// "3 of 10 products costed" count would be misleading here.
  /// 1.0 when there's no revenue at all (nothing to be incomplete about).
  double get costCoverage {
    if (totalRevenue == 0) return 1;
    final coveredRevenue = productBreakdown
        .where((p) => p.cost != null)
        .fold(0.0, (sum, p) => sum + p.revenue);
    return coveredRevenue / totalRevenue;
  }

  /// True only when every product in the breakdown has known cost —
  /// i.e. grossProfit reflects every sale, not just some of them.
  bool get hasCompleteCostData =>
      productBreakdown.isNotEmpty && productBreakdown.every((p) => p.cost != null);

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
