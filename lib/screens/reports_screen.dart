import 'package:flutter/material.dart';
import '../models/sales_report.dart';
import '../theme/app_theme.dart';

/// Sales Reports screen — answers the owner's day-to-day questions:
/// how much did I sell, what sold best, how much cash came in, how
/// many transactions, who was the cashier.
///
/// [reportBuilder] computes a SalesReport for a given date range. Not
/// wired to real data yet — pass a real builder (backed by
/// TransactionProvider) once the aggregation layer exists; until then
/// this falls back to a mock generator so the screen can be reviewed
/// and dropped in independently.
class ReportsScreen extends StatefulWidget {
  final SalesReport Function(DateTimeRange range)? reportBuilder;

  const ReportsScreen({super.key, this.reportBuilder});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _SortMode { quantity, revenue }

class _ReportsScreenState extends State<ReportsScreen> {
  DateRangePreset _preset = DateRangePreset.today;
  DateTimeRange _range = _rangeFor(DateRangePreset.today);
  late SalesReport _report;
  _SortMode _sortMode = _SortMode.revenue;

  @override
  void initState() {
    super.initState();
    _report = _build(_range);
  }

  SalesReport _build(DateTimeRange range) {
    final builder = widget.reportBuilder ?? _mockReport;
    return builder(range);
  }

  static DateTimeRange _rangeFor(DateRangePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime start;
    DateTime end;
    switch (preset) {
      case DateRangePreset.today:
        start = today;
        end = today;
        break;
      case DateRangePreset.yesterday:
        start = today.subtract(const Duration(days: 1));
        end = start;
        break;
      case DateRangePreset.thisWeek:
        start = today.subtract(Duration(days: today.weekday - 1)); // Monday
        end = today;
        break;
      case DateRangePreset.thisMonth:
        start = DateTime(today.year, today.month, 1);
        end = today;
        break;
      case DateRangePreset.custom:
        start = today;
        end = today;
        break;
    }
    return DateTimeRange(start: start, end: DateTime(end.year, end.month, end.day, 23, 59, 59));
  }

  void _selectPreset(DateRangePreset preset) {
    final range = _rangeFor(preset);
    setState(() {
      _preset = preset;
      _range = range;
      _report = _build(range);
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.ledAmber,
            surface: AppColors.slate,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final range = DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
    );
    setState(() {
      _preset = DateRangePreset.custom;
      _range = range;
      _report = _build(range);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        elevation: 0,
        title: Text('Sales Reports',
            style: AppTextStyles.body(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 900 : double.infinity),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _RangeChipRow(
                    preset: _preset,
                    customLabel: _preset == DateRangePreset.custom ? _formatRange(_range) : null,
                    onSelect: _selectPreset,
                    onCustom: _pickCustomRange,
                  ),
                  const SizedBox(height: 20),
                  _SummaryGrid(report: _report, isWide: isWide),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'BEST SELLERS',
                    trailing: _SortToggle(
                      mode: _sortMode,
                      onChanged: (m) => setState(() => _sortMode = m),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BestSellersList(report: _report, sortMode: _sortMode),
                  const SizedBox(height: 24),
                  const _SectionHeader(title: 'BY CASHIER'),
                  const SizedBox(height: 10),
                  _CashierBreakdown(report: _report),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatRange(DateTimeRange r) {
    String fmt(DateTime d) => '${d.month}/${d.day}';
    if (r.start.year == r.end.year && r.start.month == r.end.month && r.start.day == r.end.day) {
      return fmt(r.start);
    }
    return '${fmt(r.start)} – ${fmt(r.end)}';
  }
}

// ---------------------------------------------------------------------
// Date range chips
// ---------------------------------------------------------------------

class _RangeChipRow extends StatelessWidget {
  final DateRangePreset preset;
  final String? customLabel;
  final ValueChanged<DateRangePreset> onSelect;
  final VoidCallback onCustom;

  const _RangeChipRow({
    required this.preset,
    required this.customLabel,
    required this.onSelect,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('Today', DateRangePreset.today),
          const SizedBox(width: 8),
          _chip('Yesterday', DateRangePreset.yesterday),
          const SizedBox(width: 8),
          _chip('This Week', DateRangePreset.thisWeek),
          const SizedBox(width: 8),
          _chip('This Month', DateRangePreset.thisMonth),
          const SizedBox(width: 8),
          _customChip(),
        ],
      ),
    );
  }

  Widget _chip(String label, DateRangePreset value) {
    final selected = preset == value;
    return _ChipButton(label: label, selected: selected, onTap: () => onSelect(value));
  }

  Widget _customChip() {
    final selected = preset == DateRangePreset.custom;
    return _ChipButton(
      label: selected && customLabel != null ? customLabel! : 'Custom',
      selected: selected,
      icon: Icons.calendar_today_outlined,
      onTap: onCustom,
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _ChipButton({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.ledAmber.withOpacity(0.15) : AppColors.slate,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.ledAmber : AppColors.slateBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? AppColors.ledAmber : AppColors.textMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.body(
                size: 12.5,
                weight: FontWeight.w600,
                color: selected ? AppColors.ledAmber : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Summary cards
// ---------------------------------------------------------------------

class _SummaryGrid extends StatelessWidget {
  final SalesReport report;
  final bool isWide;
  const _SummaryGrid({required this.report, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      // Fixed crossAxisCount:2 + a fixed aspect ratio meant each card
      // was as wide as half the *whole browser window* on desktop —
      // with childAspectRatio 1.6 that made cards ~590px tall.
      // 4-across on wide screens keeps cards a sane, roughly-square
      // size regardless of window width.
      crossAxisCount: isWide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: isWide ? 1.15 : 1.6,
      children: [
        _SummaryCard(
          label: 'TOTAL SALES',
          value: '₱${report.totalRevenue.toStringAsFixed(2)}',
          valueColor: AppColors.ledAmber,
          subtitle: 'avg ₱${report.avgTransactionValue.toStringAsFixed(2)}/sale',
        ),
        _SummaryCard(
          label: 'CASH IN',
          value: '₱${report.cashIn.toStringAsFixed(2)}',
          valueColor: AppColors.tillGreen,
        ),
        _SummaryCard(
          label: 'TRANSACTIONS',
          value: '${report.transactionCount}',
          valueColor: AppColors.textPrimary,
        ),
        _SummaryCard(
          label: 'ITEMS SOLD',
          value: '${report.itemsSold}',
          valueColor: AppColors.textPrimary,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String? subtitle;

  const _SummaryCard({required this.label, required this.value, required this.valueColor, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: AppTextStyles.mono(size: 10.5, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.mono(size: 22, weight: FontWeight.w700, color: valueColor)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppTextStyles.body(size: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Section header + sort toggle
// ---------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: AppTextStyles.mono(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.5)),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SortToggle extends StatelessWidget {
  final _SortMode mode;
  final ValueChanged<_SortMode> onChanged;
  const _SortToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slateField,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.slateBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('Qty', _SortMode.quantity),
          _segment('₱', _SortMode.revenue),
        ],
      ),
    );
  }

  Widget _segment(String label, _SortMode value) {
    final selected = mode == value;
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.ledAmber.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            style: AppTextStyles.body(
                size: 11.5, weight: FontWeight.w700, color: selected ? AppColors.ledAmber : AppColors.textMuted)),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Best sellers
// ---------------------------------------------------------------------

class _BestSellersList extends StatelessWidget {
  final SalesReport report;
  final _SortMode sortMode;
  const _BestSellersList({required this.report, required this.sortMode});

  @override
  Widget build(BuildContext context) {
    if (report.productBreakdown.isEmpty) {
      return _EmptyState(text: 'No sales in this range');
    }

    final lines = [...report.productBreakdown];
    lines.sort((a, b) => sortMode == _SortMode.quantity
        ? b.quantitySold.compareTo(a.quantitySold)
        : b.revenue.compareTo(a.revenue));
    final top = lines.take(10).toList();
    final maxValue = sortMode == _SortMode.quantity
        ? top.first.quantitySold.toDouble()
        : top.first.revenue;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slateBorder),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: top.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final line = entry.value;
          final fraction = maxValue == 0
              ? 0.0
              : (sortMode == _SortMode.quantity ? line.quantitySold / maxValue : line.revenue / maxValue);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text('$rank',
                      style: AppTextStyles.mono(size: 12, weight: FontWeight.w700, color: AppColors.textMuted)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.displayName,
                          style: AppTextStyles.body(size: 13.5, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: fraction.clamp(0, 1),
                          minHeight: 4,
                          backgroundColor: AppColors.slateBorder,
                          valueColor: const AlwaysStoppedAnimation(AppColors.ledAmber),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${line.quantitySold} sold',
                        style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
                    Text('₱${line.revenue.toStringAsFixed(2)}',
                        style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Cashier breakdown
// ---------------------------------------------------------------------

class _CashierBreakdown extends StatelessWidget {
  final SalesReport report;
  const _CashierBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.cashierBreakdown.isEmpty) {
      return _EmptyState(text: 'No sales in this range');
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slateBorder),
      ),
      child: Column(
        children: report.cashierBreakdown.asMap().entries.map((entry) {
          final line = entry.value;
          final isLast = entry.key == report.cashierBreakdown.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.slateBorder)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.slateField,
                  child: Text(
                    line.cashierName.isNotEmpty ? line.cashierName[0].toUpperCase() : '?',
                    style: AppTextStyles.body(size: 12, weight: FontWeight.w700, color: AppColors.ledAmber),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.cashierName, style: AppTextStyles.body(size: 13.5, weight: FontWeight.w600)),
                      Text('${line.transactionCount} transaction${line.transactionCount == 1 ? '' : 's'}',
                          style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Text('₱${line.revenue.toStringAsFixed(2)}',
                    style: AppTextStyles.mono(size: 13.5, weight: FontWeight.w700, color: AppColors.tillGreen)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slateBorder),
      ),
      child: Center(
        child: Text(text, style: AppTextStyles.body(size: 13, color: AppColors.textMuted)),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Mock data — stands in until the real aggregation provider exists.
// Deterministic-ish but scales with the selected range so the screen
// looks reasonable to review at every preset.
// ---------------------------------------------------------------------

SalesReport _mockReport(DateTimeRange range) {
  final days = range.end.difference(range.start).inDays + 1;
  final scale = days.clamp(1, 30);

  final products = <ProductSalesLine>[
    ProductSalesLine(productId: 'p1', variantId: 'v1', displayName: 'Coffee (Large)', quantitySold: 18 * scale, revenue: 18 * scale * 65.0),
    ProductSalesLine(productId: 'p1', variantId: 'v2', displayName: 'Coffee (Medium)', quantitySold: 12 * scale, revenue: 12 * scale * 55.0),
    ProductSalesLine(productId: 'p2', displayName: 'Iced Tea', quantitySold: 10 * scale, revenue: 10 * scale * 45.0),
    ProductSalesLine(productId: 'p3', displayName: 'Croissant', quantitySold: 7 * scale, revenue: 7 * scale * 60.0),
    ProductSalesLine(productId: 'p4', displayName: 'Bottled Water', quantitySold: 15 * scale, revenue: 15 * scale * 20.0),
    ProductSalesLine(productId: 'p5', displayName: 'Chips', quantitySold: 5 * scale, revenue: 5 * scale * 35.0),
  ];

  final cashiers = <CashierSalesLine>[
    CashierSalesLine(cashierName: 'Maria', transactionCount: 14 * scale, revenue: 14 * scale * 130.0),
    CashierSalesLine(cashierName: 'Jun', transactionCount: 9 * scale, revenue: 9 * scale * 118.0),
  ];

  final totalRevenue = products.fold(0.0, (sum, p) => sum + p.revenue);
  final transactionCount = cashiers.fold(0, (sum, c) => sum + c.transactionCount);
  final itemsSold = products.fold(0, (sum, p) => sum + p.quantitySold);

  return SalesReport(
    rangeStart: range.start,
    rangeEnd: range.end,
    totalRevenue: totalRevenue,
    cashIn: totalRevenue,
    transactionCount: transactionCount,
    itemsSold: itemsSold,
    productBreakdown: products,
    cashierBreakdown: cashiers,
  );
}
