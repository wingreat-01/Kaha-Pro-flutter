import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/employee.dart';
import '../services/export/data_exports.dart';
import '../services/export/file_export.dart';
import '../state/currency_provider.dart';
import '../state/ingredient_provider.dart';
import '../state/payroll_provider.dart';
import '../state/product_provider.dart';
import '../state/transaction_provider.dart';
import '../theme/app_theme.dart';

String _date(DateTime d) => '${d.month}/${d.day}/${d.year}';

/// Settings → Export Data (admin only). Every export is a CSV that opens in
/// Excel, Google Sheets or Numbers.
class ExportDataScreen extends StatefulWidget {
  const ExportDataScreen({super.key});

  @override
  State<ExportDataScreen> createState() => _ExportDataScreenState();
}

class _ExportDataScreenState extends State<ExportDataScreen> {
  late DateTimeRange _salesRange = _thisMonth();
  late DateTimeRange _timeRange = _thisMonth();
  late Future<List<PayrollRun>> _runs;
  PayrollRun? _run;
  // Which export is running, so only its button shows a spinner.
  String? _busy;

  static DateTimeRange _thisMonth() {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month, now.day));
  }

  @override
  void initState() {
    super.initState();
    final payroll = context.read<PayrollProvider>();
    _runs = payroll.loadRuns().then((runs) {
      if (mounted && runs.isNotEmpty) setState(() => _run = runs.first);
      return runs;
    });
  }

  Future<DateTimeRange?> _pickRange(DateTimeRange current) {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: current,
    );
  }

  /// Builds the file with [build], then saves/shares it. An empty export
  /// is reported instead of handing over a header-only file.
  Future<void> _export(String key, Future<ExportFile> Function() build) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await build();
      if (file.rowCount == 0) {
        messenger.showSnackBar(const SnackBar(content: Text('Nothing to export for that selection.')));
        return;
      }
      final message = await saveExportFile(file.filename, file.bytes);
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text('$message (${file.rowCount} rows)'), duration: const Duration(seconds: 6)));
      }
    } catch (e) {
      debugPrint('export $key failed: $e');
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.ledgerRed,
        content: const Text('Export failed. Check your connection and try again.'),
      ));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactions = context.read<TransactionProvider>();
    final products = context.read<ProductProvider>();
    final ingredients = context.read<IngredientProvider>();
    final payroll = context.read<PayrollProvider>();

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('Export Data', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Exports are CSV files — open them in Excel, Google Sheets or Numbers. '
            'On a phone you can save them to Files/Drive or send them by email or chat.',
            style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          _Section(
            icon: Icons.point_of_sale_outlined,
            title: 'Sales',
            children: [
              _RangeButton(
                range: _salesRange,
                onTap: () async {
                  final r = await _pickRange(_salesRange);
                  if (r != null) setState(() => _salesRange = r);
                },
              ),
              _ExportButton(
                label: 'Sales transactions',
                hint: 'One row per sale — totals, payment, discount, voids',
                busy: _busy == 'sales',
                onTap: () => _export(
                  'sales',
                  () async => salesTransactionsExport(transactions.transactions, _salesRange.start, _salesRange.end),
                ),
              ),
              _ExportButton(
                label: 'Items sold',
                hint: 'One row per item line — for totals by product or category',
                busy: _busy == 'items',
                onTap: () => _export(
                  'items',
                  () async => salesItemsExport(transactions.transactions, _salesRange.start, _salesRange.end),
                ),
              ),
            ],
          ),
          _Section(
            icon: Icons.inventory_2_outlined,
            title: 'Inventory (current stock)',
            children: [
              _ExportButton(
                label: 'Product stock',
                hint: 'Every product (and size with its own stock), price, cost, stock value',
                busy: _busy == 'products',
                onTap: () => _export('products', () async => productStockExport(products.products, DateTime.now())),
              ),
              _ExportButton(
                label: 'Ingredient stock',
                hint: 'Every ingredient, unit, cost and stock value',
                busy: _busy == 'ingredients',
                onTap: () => _export('ingredients', () async {
                  if (ingredients.ingredients.isEmpty) await ingredients.loadFromSupabase();
                  return ingredientStockExport(ingredients.ingredients, DateTime.now());
                }),
              ),
            ],
          ),
          _Section(
            icon: Icons.badge_outlined,
            title: 'Payroll',
            children: [
              FutureBuilder<List<PayrollRun>>(
                future: _runs,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
                  }
                  final runs = snap.data ?? const <PayrollRun>[];
                  if (snap.hasError || runs.isEmpty) {
                    return Text(
                      snap.hasError ? 'Could not load saved payrolls.' : 'No saved payrolls yet.',
                      style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
                    );
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: _run?.id,
                    isExpanded: true,
                    dropdownColor: AppColors.slate,
                    decoration: const InputDecoration(labelText: 'Saved payroll'),
                    items: [
                      for (final r in runs)
                        DropdownMenuItem(
                          value: r.id,
                          child: Text('${_date(r.periodStart)} – ${_date(r.periodEnd)} · ${context.money(r.totalNet)}'),
                        ),
                    ],
                    onChanged: (id) => setState(() => _run = runs.firstWhere((r) => r.id == id)),
                  );
                },
              ),
              _ExportButton(
                label: 'Payroll (payslips)',
                hint: 'One row per employee — pay, deductions, net pay',
                busy: _busy == 'payroll',
                onTap: _run == null
                    ? null
                    : () => _export('payroll', () async {
                          final run = _run!;
                          return payrollRunExport(run, await payroll.loadRunLines(run.id));
                        }),
              ),
              const Divider(height: 24),
              _RangeButton(
                range: _timeRange,
                onTap: () async {
                  final r = await _pickRange(_timeRange);
                  if (r != null) setState(() => _timeRange = r);
                },
              ),
              _ExportButton(
                label: 'Time records',
                hint: 'Every time-in / time-out with hours worked',
                busy: _busy == 'time',
                onTap: () => _export('time', () async {
                  if (payroll.employees.isEmpty) await payroll.loadEmployees();
                  final entries = await payroll.loadEntries(_timeRange.start, _timeRange.end);
                  final names = {for (final e in payroll.employees) e.id: e.name};
                  return timeRecordsExport(entries, names, _timeRange.start, _timeRange.end);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _Section({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.ledAmber, size: 20),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  final DateTimeRange range;
  final VoidCallback onTap;
  const _RangeButton({required this.range, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.date_range, size: 18),
        label: Text('${_date(range.start)} – ${_date(range.end)}'),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final String label;
  final String hint;
  final bool busy;
  final VoidCallback? onTap;
  const _ExportButton({required this.label, required this.hint, required this.busy, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      onTap: busy ? null : onTap,
      title: Text(label, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
      subtitle: Text(hint, style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
      trailing: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.file_download_outlined, color: onTap == null ? AppColors.textMuted : AppColors.ledAmber),
    );
  }
}
