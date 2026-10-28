import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/employee.dart';
import '../../state/currency_provider.dart';
import '../../state/payroll_provider.dart';
import '../../theme/app_theme.dart';
import '../time_clock_screen.dart';
import 'payroll_tab.dart';
import 'time_records_tab.dart';

/// Settings → Employees & Payroll (admin only, like the rest of Settings).
/// Employees (rates, schedules, PINs), Time Records (punches + photos,
/// corrections) and Payroll (compute, adjust, save, payslips).
class PayrollHubScreen extends StatefulWidget {
  // Logged-in admin — recorded on corrections and saved payroll runs.
  final String staffName;
  const PayrollHubScreen({super.key, required this.staffName});

  @override
  State<PayrollHubScreen> createState() => _PayrollHubScreenState();
}

class _PayrollHubScreenState extends State<PayrollHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final payroll = context.read<PayrollProvider>();
      payroll.loadEmployees();
      // Expire old punch photos (once a day) — see PayrollProvider.
      await payroll.loadPhotoSettings();
      payroll.purgeOldPhotos();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.charcoal,
        appBar: AppBar(
          backgroundColor: AppColors.charcoal,
          elevation: 0,
          title: Text('Employees & Payroll', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TimeClockScreen())),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('Time Clock'),
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.ledAmber,
            labelColor: AppColors.ledAmber,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: const [
              Tab(text: 'Employees'),
              Tab(text: 'Time Records'),
              Tab(text: 'Payroll'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _EmployeesTab(),
            TimeRecordsTab(staffName: widget.staffName),
            PayrollTab(staffName: widget.staffName),
          ],
        ),
      ),
    );
  }
}

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab();

  @override
  Widget build(BuildContext context) {
    final payroll = context.watch<PayrollProvider>();
    final employees = payroll.employees;
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ledAmber,
        foregroundColor: AppColors.charcoal,
        onPressed: () => showEmployeeDialog(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add employee'),
      ),
      body: payroll.loading && employees.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : employees.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      payroll.error ??
                          'No employees yet. Add one with their daily rate, schedule and a PIN for the time clock.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: employees.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final e = employees[i];
                    return Material(
                      color: AppColors.slate,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.slateBorder),
                        ),
                        onTap: () => showEmployeeDialog(context, existing: e),
                        title: Text(
                          e.name,
                          style: AppTextStyles.body(
                            size: 14.5,
                            weight: FontWeight.w700,
                            color: e.isActive ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                        ),
                        subtitle: Text(
                          '${context.money(e.dailyRate)}/day · ${formatClock(e.shiftStartMinutes)}–${formatClock(e.shiftEndMinutes)}'
                          '${e.position == null ? '' : ' · ${e.position}'}',
                          style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
                        ),
                        trailing: !e.isActive
                            ? Text('INACTIVE', style: AppTextStyles.mono(size: 10, color: AppColors.textMuted))
                            : !e.hasPin
                                ? Text('NO PIN', style: AppTextStyles.mono(size: 10, color: AppColors.ledgerRed))
                                : Icon(Icons.chevron_right, color: AppColors.textMuted),
                      ),
                    );
                  },
                ),
    );
  }
}

Future<void> showEmployeeDialog(BuildContext context, {Employee? existing}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EmployeeDialog(existing: existing),
  );
}

class _EmployeeDialog extends StatefulWidget {
  final Employee? existing;
  const _EmployeeDialog({this.existing});

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _position = TextEditingController(text: widget.existing?.position ?? '');
  late final _rate = TextEditingController(
      text: widget.existing == null ? '' : widget.existing!.dailyRate.toStringAsFixed(2));
  late final _break = TextEditingController(text: '${widget.existing?.breakMinutes ?? 60}');
  late final _grace = TextEditingController(text: '${widget.existing?.lateGraceMinutes ?? 0}');
  final _pin = TextEditingController();
  late int _start = widget.existing?.shiftStartMinutes ?? 8 * 60;
  late int _end = widget.existing?.shiftEndMinutes ?? 17 * 60;
  late bool _active = widget.existing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    for (final c in [_name, _position, _rate, _break, _grace, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      final m = picked.hour * 60 + picked.minute;
      if (start) {
        _start = m;
      } else {
        _end = m;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final rate = double.tryParse(_rate.text.trim());
    final breakMin = int.tryParse(_break.text.trim());
    final grace = int.tryParse(_grace.text.trim());
    final pin = _pin.text.trim();
    String? error;
    if (name.isEmpty) {
      error = 'Name is required.';
    } else if (rate == null || rate < 0) {
      error = 'Enter a valid daily rate.';
    } else if (breakMin == null || breakMin < 0) {
      error = 'Enter the unpaid break in minutes (0 if none).';
    } else if (grace == null || grace < 0 || grace > 120) {
      error = 'Grace period must be 0–120 minutes.';
    } else if (_isNew && pin.isEmpty) {
      error = 'Set a PIN so they can use the time clock.';
    } else if (pin.isNotEmpty && (pin.length < 4 || pin.length > 8)) {
      error = 'PIN must be 4 to 8 digits.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final employee = Employee(
      id: widget.existing?.id ?? '',
      name: name,
      position: _position.text,
      dailyRate: rate!,
      shiftStartMinutes: _start,
      shiftEndMinutes: _end,
      breakMinutes: breakMin!,
      lateGraceMinutes: grace!,
      isActive: _active,
    );
    if (employee.paidMinutes <= 1) {
      setState(() => _error = 'The break is as long as the whole shift.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<PayrollProvider>().saveEmployee(employee, pin: pin.isEmpty ? null : pin);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('saveEmployee failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is StateError ? e.message : 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final overnight = _end <= _start;
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text(_isNew ? 'Add employee' : 'Edit employee',
          style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: _position, decoration: const InputDecoration(labelText: 'Position (optional)')),
              const SizedBox(height: 8),
              TextField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Daily rate'),
              ),
              const SizedBox(height: 14),
              Text('SCHEDULE', style: AppTextStyles.mono(size: 10, color: AppColors.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(true),
                      child: Text('Start ${formatClock(_start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(false),
                      child: Text('End ${formatClock(_end)}'),
                    ),
                  ),
                ],
              ),
              if (overnight)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Overnight shift — ends the next day.',
                      style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _break,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Unpaid break (min)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _grace,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Late grace (min)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: _isNew
                      ? 'Time clock PIN (4–8 digits)'
                      : widget.existing!.hasPin
                          ? 'New PIN (leave blank to keep)'
                          : 'Time clock PIN (not set yet)',
                  counterText: '',
                ),
              ),
              if (!_isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: Text('Active', style: AppTextStyles.body(size: 14)),
                  subtitle: Text('Inactive employees can\'t clock in. Past records and payslips are kept.',
                      style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
