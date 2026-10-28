import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/employee.dart';
import '../../state/currency_provider.dart';
import '../../state/payroll_provider.dart';
import '../../theme/app_theme.dart';

String _date(DateTime d) => '${d.month}/${d.day}/${d.year}';
String _hm(int minutes) => minutes == 0 ? '0m' : '${minutes ~/ 60}h ${minutes % 60}m';

/// Pick a period → compute from time records → add allowances /
/// deductions per employee → save. Saved runs keep a snapshot, so later
/// rate or schedule changes never alter a past payslip.
class PayrollTab extends StatefulWidget {
  final String staffName;
  const PayrollTab({super.key, required this.staffName});

  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> {
  DateTimeRange? _range;
  bool _payOvertime = false;
  final _otMultiplier = TextEditingController(text: '1.25');
  List<PayrollLine>? _lines;
  bool _computing = false;
  bool _saving = false;
  String? _error;
  late Future<List<PayrollRun>> _runs;

  @override
  void initState() {
    super.initState();
    _runs = context.read<PayrollProvider>().loadRuns();
  }

  @override
  void dispose() {
    _otMultiplier.dispose();
    super.dispose();
  }

  double get _multiplier => double.tryParse(_otMultiplier.text.trim()) ?? 1.25;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _range = picked;
      _lines = null;
    });
  }

  Future<void> _compute() async {
    final range = _range;
    if (range == null) return;
    setState(() {
      _computing = true;
      _error = null;
    });
    try {
      final lines = await context.read<PayrollProvider>().computePayroll(
            range.start,
            range.end,
            payOvertime: _payOvertime,
            overtimeMultiplier: _multiplier,
          );
      if (!mounted) return;
      // Keep adjustments already typed in for the same employees.
      final previous = {for (final l in _lines ?? const <PayrollLine>[]) l.employeeId: l.adjustments};
      setState(() {
        _lines = lines.map((l) => l.withAdjustments(previous[l.employeeId] ?? const [])).toList();
        _computing = false;
      });
    } catch (e) {
      debugPrint('computePayroll failed: $e');
      if (mounted) {
        setState(() {
          _computing = false;
          _error = 'Could not compute payroll. Check your connection.';
        });
      }
    }
  }

  Future<void> _editLine(int index) async {
    final updated = await showDialog<List<PayAdjustment>>(
      context: context,
      builder: (_) => _AdjustmentsDialog(line: _lines![index]),
    );
    if (updated != null) setState(() => _lines![index] = _lines![index].withAdjustments(updated));
  }

  Future<void> _save() async {
    final lines = _lines;
    final range = _range;
    if (lines == null || range == null || lines.isEmpty) return;
    final review = lines.fold(0, (sum, l) => sum + l.daysNeedingReview);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: const Text('Save payroll?'),
        content: Text(
          '${_date(range.start)} – ${_date(range.end)} · ${lines.length} employee${lines.length == 1 ? '' : 's'} · '
          'total net ${c.money(lines.fold(0.0, (s, l) => s + l.netPay))}.'
          '${review > 0 ? '\n\n$review day${review == 1 ? '' : 's'} still need review in Time Records and are NOT paid in this run.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<PayrollProvider>().saveRun(
            from: range.start,
            to: range.end,
            payOvertime: _payOvertime,
            overtimeMultiplier: _multiplier,
            lines: lines,
            createdBy: widget.staffName,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _lines = null;
        _runs = context.read<PayrollProvider>().loadRuns();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payroll saved.')));
    } catch (e) {
      debugPrint('saveRun failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save payroll. Check your connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final range = _range;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('NEW PAYROLL', style: AppTextStyles.mono(size: 10.5, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(range == null ? 'Choose pay period' : '${_date(range.start)} – ${_date(range.end)}'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _payOvertime,
          onChanged: (v) => setState(() {
            _payOvertime = v;
            _lines = null;
          }),
          title: Text('Pay overtime', style: AppTextStyles.body(size: 14)),
          subtitle: Text(
            'Time after the scheduled shift end. Off = shown but not paid.',
            style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
          ),
        ),
        if (_payOvertime)
          TextField(
            controller: _otMultiplier,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(
              labelText: 'Overtime rate multiplier',
              helperText: 'e.g. 1.25 = regular rate + 25%. Confirm the rate that applies to your business.',
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() => _lines = null),
          ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: range == null || _computing ? null : _compute,
          child: _computing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Compute payroll'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
        ],
        if (lines != null) ...[
          const SizedBox(height: 16),
          if (lines.isEmpty)
            Text('No employees to pay for this period.', style: AppTextStyles.body(size: 13, color: AppColors.textMuted)),
          for (var i = 0; i < lines.length; i++) ...[
            _LineCard(line: lines[i], onTap: () => _editLine(i)),
            const SizedBox(height: 8),
          ],
          if (lines.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text('TOTAL NET',
                      style: AppTextStyles.mono(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
                Text(
                  context.money(lines.fold(0.0, (s, l) => s + l.netPay)),
                  style: AppTextStyles.mono(size: 18, weight: FontWeight.w700, color: AppColors.ledAmber),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.tillGreen),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save payroll'),
            ),
          ],
        ],
        const SizedBox(height: 28),
        Text('SAVED PAYROLLS', style: AppTextStyles.mono(size: 10.5, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        FutureBuilder<List<PayrollRun>>(
          future: _runs,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Text('Could not load saved payrolls.', style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed));
            }
            final runs = snap.data!;
            if (runs.isEmpty) {
              return Text('None yet.', style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted));
            }
            return Column(
              children: [
                for (final r in runs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_date(r.periodStart)} – ${_date(r.periodEnd)}',
                        style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                    subtitle: Text(
                      'Saved ${_date(r.createdAt)}${r.createdBy == null ? '' : ' by ${r.createdBy}'}',
                      style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                    ),
                    trailing: Text(context.money(r.totalNet),
                        style: AppTextStyles.mono(size: 14, weight: FontWeight.w700, color: AppColors.ledAmber)),
                    onTap: () async {
                      final deleted = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => _RunDetailScreen(run: r)),
                      );
                      if (deleted == true && mounted) {
                        setState(() => _runs = context.read<PayrollProvider>().loadRuns());
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  final PayrollLine line;
  final VoidCallback? onTap;
  const _LineCard({required this.line, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.slate,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: line.daysNeedingReview > 0 ? AppColors.ledAmber.withValues(alpha: 0.6) : AppColors.slateBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(line.employeeName, style: AppTextStyles.body(size: 14.5, weight: FontWeight.w700))),
                  Text(context.money(line.netPay),
                      style: AppTextStyles.mono(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${line.daysWorked} day${line.daysWorked == 1 ? '' : 's'} × ${context.money(line.dailyRate)} · '
                'late ${_hm(line.lateMinutes)} · under ${_hm(line.undertimeMinutes)} · OT ${_hm(line.overtimeMinutes)}'
                '${line.adjustments.isEmpty ? '' : ' · ${line.adjustments.length} adjustment${line.adjustments.length == 1 ? '' : 's'}'}',
                style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
              ),
              if (line.daysNeedingReview > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${line.daysNeedingReview} day${line.daysNeedingReview == 1 ? '' : 's'} need review in Time Records (not paid).',
                    style: AppTextStyles.body(size: 11.5, color: AppColors.ledAmber),
                  ),
                ),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Tap to add allowances or deductions',
                      style: AppTextStyles.body(size: 11, color: AppColors.ledAmber)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdjustmentsDialog extends StatefulWidget {
  final PayrollLine line;
  const _AdjustmentsDialog({required this.line});

  @override
  State<_AdjustmentsDialog> createState() => _AdjustmentsDialogState();
}

class _AdjustmentsDialogState extends State<_AdjustmentsDialog> {
  late final List<PayAdjustment> _items = [...widget.line.adjustments];
  final _label = TextEditingController();
  final _amount = TextEditingController();
  bool _deduction = true;
  String? _error;

  static const _quickDeductions = ['SSS', 'PhilHealth', 'Pag-IBIG', 'Withholding tax', 'Cash advance'];

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _add() {
    final label = _label.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    if (label.isEmpty || amount == null || amount <= 0) {
      setState(() => _error = 'Enter a label and an amount above 0.');
      return;
    }
    setState(() {
      _items.add(PayAdjustment(label: label, amount: amount, isDeduction: _deduction));
      _label.clear();
      _amount.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.line.withAdjustments(_items);
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text(widget.line.employeeName, style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PayslipBody(line: preview),
              const Divider(height: 24),
              for (var i = 0; i < _items.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: Text('${_items[i].isDeduction ? '−' : '+'} ${_items[i].label}',
                          style: AppTextStyles.body(size: 13)),
                    ),
                    Text(context.money(_items[i].amount), style: AppTextStyles.mono(size: 13)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _items.removeAt(i)),
                      icon: Icon(Icons.close, size: 16, color: AppColors.textMuted),
                    ),
                  ],
                ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Addition')),
                  ButtonSegment(value: true, label: Text('Deduction')),
                ],
                selected: {_deduction},
                onSelectionChanged: (s) => setState(() => _deduction = s.first),
              ),
              const SizedBox(height: 8),
              if (_deduction)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final q in _quickDeductions)
                      ActionChip(label: Text(q), onPressed: () => setState(() => _label.text = q)),
                  ],
                ),
              TextField(
                controller: _label,
                decoration: InputDecoration(labelText: _deduction ? 'Deduction (e.g. Cash advance)' : 'Addition (e.g. Allowance)'),
              ),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount'),
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add')),
              ),
              if (_error != null) Text(_error!, style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_items), child: const Text('Done')),
      ],
    );
  }
}

/// Payslip figures — shared by the adjustments preview and saved runs.
class _PayslipBody extends StatelessWidget {
  final PayrollLine line;
  const _PayslipBody({required this.line});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, double amount, {bool bold = false, Color? color, bool minus = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.body(size: 13, weight: bold ? FontWeight.w700 : FontWeight.w400))),
              Text(
                '${minus && amount > 0 ? '−' : ''}${context.money(amount)}',
                style: AppTextStyles.mono(size: 13, weight: bold ? FontWeight.w700 : FontWeight.w500, color: color),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Basic (${line.daysWorked} × ${context.money(line.dailyRate)})', line.basicPay),
        if (line.overtimePay > 0) row('Overtime (${_hm(line.overtimeMinutes)})', line.overtimePay),
        for (final a in line.adjustments.where((a) => !a.isDeduction)) row(a.label, a.amount),
        row('Gross pay', line.grossPay, bold: true),
        if (line.lateDeduction > 0) row('Late (${_hm(line.lateMinutes)})', line.lateDeduction, minus: true),
        if (line.undertimeDeduction > 0) row('Undertime (${_hm(line.undertimeMinutes)})', line.undertimeDeduction, minus: true),
        for (final a in line.adjustments.where((a) => a.isDeduction)) row(a.label, a.amount, minus: true),
        row('Total deductions', line.totalDeductions, bold: true, minus: true),
        const Divider(),
        row('NET PAY', line.netPay, bold: true, color: AppColors.ledAmber),
      ],
    );
  }
}

String _payslipText(BuildContext context, PayrollRun run, PayrollLine l) {
  final b = StringBuffer()
    ..writeln('PAYSLIP — ${l.employeeName}')
    ..writeln('Period: ${_date(run.periodStart)} – ${_date(run.periodEnd)}')
    ..writeln('')
    ..writeln('Basic: ${l.daysWorked} day(s) × ${context.money(l.dailyRate)} = ${context.money(l.basicPay)}');
  if (l.overtimePay > 0) b.writeln('Overtime (${_hm(l.overtimeMinutes)}): ${context.money(l.overtimePay)}');
  for (final a in l.adjustments.where((a) => !a.isDeduction)) {
    b.writeln('${a.label}: ${context.money(a.amount)}');
  }
  b.writeln('Gross pay: ${context.money(l.grossPay)}');
  if (l.lateDeduction > 0) b.writeln('Late (${_hm(l.lateMinutes)}): -${context.money(l.lateDeduction)}');
  if (l.undertimeDeduction > 0) b.writeln('Undertime (${_hm(l.undertimeMinutes)}): -${context.money(l.undertimeDeduction)}');
  for (final a in l.adjustments.where((a) => a.isDeduction)) {
    b.writeln('${a.label}: -${context.money(a.amount)}');
  }
  b
    ..writeln('Total deductions: ${context.money(l.totalDeductions)}')
    ..writeln('')
    ..writeln('NET PAY: ${context.money(l.netPay)}');
  return b.toString();
}

class _RunDetailScreen extends StatelessWidget {
  final PayrollRun run;
  const _RunDetailScreen({required this.run});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: const Text('Delete this payroll?'),
        content: const Text('Its payslips are deleted. Time records are not affected. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.ledgerRed)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<PayrollProvider>().deleteRun(run.id);
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('deleteRun failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('${_date(run.periodStart)} – ${_date(run.periodEnd)}',
            style: AppTextStyles.mono(size: 15, weight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: () => _delete(context), icon: const Icon(Icons.delete_outline), tooltip: 'Delete payroll'),
        ],
      ),
      body: FutureBuilder<List<PayrollLine>>(
        future: context.read<PayrollProvider>().loadRunLines(run.id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(child: Text('Could not load payslips.', style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)));
          }
          final lines = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final l in lines)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.slate,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slateBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(l.employeeName, style: AppTextStyles.body(size: 15, weight: FontWeight.w700))),
                          IconButton(
                            tooltip: 'Share payslip',
                            icon: const Icon(Icons.share_outlined, size: 20),
                            onPressed: () => Share.share(_payslipText(context, run, l), subject: 'Payslip — ${l.employeeName}'),
                          ),
                        ],
                      ),
                      _PayslipBody(line: l),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
