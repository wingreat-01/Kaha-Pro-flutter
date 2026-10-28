import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/employee.dart';
import '../../state/payroll_provider.dart';
import '../../theme/app_theme.dart';

String _clock(DateTime t) => formatClock(t.hour * 60 + t.minute);
String _date(DateTime d) => '${d.month}/${d.day}/${d.year}';
String _hours(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

/// Every punch in a date range with its selfies, so the owner can check
/// who actually clocked in, fix missed time-outs, and add manual entries.
class TimeRecordsTab extends StatefulWidget {
  final String staffName;
  const TimeRecordsTab({super.key, required this.staffName});

  @override
  State<TimeRecordsTab> createState() => _TimeRecordsTabState();
}

class _TimeRecordsTabState extends State<TimeRecordsTab> {
  late DateTimeRange _range = _lastDays(7);
  String? _employeeFilter;
  List<TimeEntry> _entries = [];
  bool _loading = false;
  String? _error;

  static DateTimeRange _lastDays(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: today.subtract(Duration(days: days - 1)), end: today);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await context.read<PayrollProvider>().loadEntries(_range.start, _range.end);
      if (!mounted) return;
      setState(() {
        // loadEntries reaches a day early for overnight shifts; this list
        // shows only the chosen dates.
        _entries = entries.where((e) {
          final d = DateTime(e.clockIn.year, e.clockIn.month, e.clockIn.day);
          return !d.isBefore(_range.start) && !d.isAfter(_range.end);
        }).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('loadEntries failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load time records. Check your connection.';
        });
      }
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  Future<void> _changeRetention(int days) async {
    final payroll = context.read<PayrollProvider>();
    if (days < payroll.photoRetentionDays) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppColors.slate,
          title: Text('Keep photos for $days days?'),
          content: Text(
            'Time clock photos older than $days days are deleted now. Time records stay. This can\'t be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete old photos')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final removed = await payroll.setPhotoRetentionDays(days);
    if (!mounted) return;
    if (removed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $removed old photo${removed == 1 ? '' : 's'}.')),
      );
    }
    _load();
  }

  Future<void> _edit({TimeEntry? entry}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EntryDialog(entry: entry, staffName: widget.staffName),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<PayrollProvider>().employees;
    final names = {for (final e in employees) e.id: e.name};
    final shown = _employeeFilter == null ? _entries : _entries.where((e) => e.employeeId == _employeeFilter).toList();
    final reviewCount = shown.where((e) => e.needsReview || e.isOpen).length;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ledAmber,
        foregroundColor: AppColors.charcoal,
        onPressed: employees.isEmpty ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Manual entry'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text('${_date(_range.start)} – ${_date(_range.end)}'),
                ),
                DropdownButton<String?>(
                  value: _employeeFilter,
                  dropdownColor: AppColors.slate,
                  hint: const Text('All employees'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All employees')),
                    for (final e in employees) DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: (v) => setState(() => _employeeFilter = v),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Photos kept for ', style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted)),
                    DropdownButton<int>(
                      value: context.watch<PayrollProvider>().photoRetentionDays,
                      dropdownColor: AppColors.slate,
                      items: [
                        for (final d in PayrollProvider.retentionChoices)
                          DropdownMenuItem(value: d, child: Text('$d days')),
                      ],
                      onChanged: (d) => d == null ? null : _changeRetention(d),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (reviewCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '$reviewCount record${reviewCount == 1 ? '' : 's'} need a time-out or review before payroll.',
                style: AppTextStyles.body(size: 12.5, color: AppColors.ledAmber),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)))
                    : shown.isEmpty
                        ? Center(
                            child: Text('No time records in this range.',
                                style: AppTextStyles.body(size: 13, color: AppColors.textMuted)),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                              itemCount: shown.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) => _EntryRow(
                                entry: shown[i],
                                employeeName: names[shown[i].employeeId] ?? 'Removed employee',
                                onTap: () => _edit(entry: shown[i]),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final TimeEntry entry;
  final String employeeName;
  final VoidCallback onTap;

  const _EntryRow({required this.entry, required this.employeeName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final flagged = entry.needsReview || entry.isOpen;
    // Clock punches past the retention period lost their photos on purpose.
    final expired = entry.source == 'clock' && entry.clockIn.isBefore(context.read<PayrollProvider>().photoCutoff);
    final range = entry.isOpen
        ? '${_clock(entry.clockIn)} – still in'
        : '${_clock(entry.clockIn)} – ${_clock(entry.clockOut!)} · ${_hours(entry.workedMinutes)}';
    return Material(
      color: AppColors.slate,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: flagged ? AppColors.ledAmber.withValues(alpha: 0.6) : AppColors.slateBorder),
          ),
          child: Row(
            children: [
              _PhotoThumb(path: entry.inPhotoPath, label: expired ? 'EXP' : 'IN'),
              const SizedBox(width: 6),
              _PhotoThumb(path: entry.outPhotoPath, label: expired ? 'EXP' : 'OUT'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employeeName, style: AppTextStyles.body(size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${_date(entry.clockIn)} · $range',
                        style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
                    if (entry.source == 'manual' || entry.needsReview || entry.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [
                            if (entry.needsReview) 'NEEDS REVIEW',
                            if (entry.source == 'manual') 'Manual',
                            if (entry.editedBy != null) 'edited by ${entry.editedBy}',
                            if (entry.note != null) entry.note!,
                          ].join(' · '),
                          style: AppTextStyles.body(
                            size: 11.5,
                            color: entry.needsReview ? AppColors.ledAmber : AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed-URL thumbnail of a punch selfie (private bucket); tap to enlarge.
class _PhotoThumb extends StatefulWidget {
  final String? path;
  final String label;
  const _PhotoThumb({required this.path, required this.label});

  @override
  State<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<_PhotoThumb> {
  // Fetched once per thumbnail, not on every rebuild of the list.
  late final Future<String?>? _url =
      widget.path == null ? null : context.read<PayrollProvider>().photoUrl(widget.path!);

  String get label => widget.label;

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(color: AppColors.slateField, borderRadius: BorderRadius.circular(8));
    if (_url == null) {
      return Container(
        width: 44,
        height: 44,
        decoration: box,
        alignment: Alignment.center,
        child: Text(label, style: AppTextStyles.mono(size: 9, color: AppColors.textMuted)),
      );
    }
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        final url = snap.data;
        return GestureDetector(
          onTap: url == null
              ? null
              : () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.black,
                      child: Stack(
                        children: [
                          InteractiveViewer(child: Image.network(url)),
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Text(label, style: AppTextStyles.mono(size: 12, color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
          child: Container(
            width: 44,
            height: 44,
            decoration: box,
            clipBehavior: Clip.antiAlias,
            child: url == null
                ? null
                : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 18)),
          ),
        );
      },
    );
  }
}

class _EntryDialog extends StatefulWidget {
  final TimeEntry? entry;
  final String staffName;
  const _EntryDialog({this.entry, required this.staffName});

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late String? _employeeId = widget.entry?.employeeId;
  late DateTime _in = widget.entry?.clockIn ?? _todayAt(8, 0);
  // A missed time-out was auto-closed at its own start; offer a blank
  // time-out instead of that zero-length one.
  late DateTime? _out = widget.entry == null
      ? _todayAt(17, 0)
      : (widget.entry!.needsReview && widget.entry!.workedMinutes == 0 ? null : widget.entry!.clockOut);
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  bool _saving = false;
  String? _error;

  static DateTime _todayAt(int h, int m) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, h, m);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (_employeeId == null) {
      setState(() => _error = 'Choose an employee.');
      return;
    }
    if (_out != null && _out!.isBefore(_in)) {
      setState(() => _error = 'Time-out is before time-in.');
      return;
    }
    if (_out != null && _out!.difference(_in).inHours >= 24) {
      setState(() => _error = 'A single entry can\'t be 24 hours or longer.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<PayrollProvider>().saveEntry(
            id: widget.entry?.id,
            employeeId: _employeeId!,
            clockIn: _in,
            clockOut: _out,
            note: _note.text,
            editedBy: widget.staffName,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('saveEntry failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        // The one-open-entry-per-employee index is the likely culprit.
        _error = _out == null
            ? 'Could not save. This employee may already be timed in elsewhere.'
            : 'Could not save. Check your connection and try again.';
      });
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: const Text('Delete this time record?'),
        content: const Text('Its photos are deleted too. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.ledgerRed)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<PayrollProvider>().deleteEntry(widget.entry!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('deleteEntry failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not delete. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<PayrollProvider>().employees;
    final isNew = widget.entry == null;
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text(isNew ? 'Manual time entry' : 'Edit time record',
          style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _employeeId,
              dropdownColor: AppColors.slate,
              decoration: const InputDecoration(labelText: 'Employee'),
              items: [for (final e in employees) DropdownMenuItem(value: e.id, child: Text(e.name))],
              onChanged: isNew ? (v) => setState(() => _employeeId = v) : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final picked = await _pick(_in);
                if (picked != null) setState(() => _in = picked);
              },
              child: Text('Time in: ${_date(_in)} ${_clock(_in)}'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await _pick(_out ?? _in);
                      if (picked != null) setState(() => _out = picked);
                    },
                    child: Text(_out == null ? 'Time out: not set' : 'Time out: ${_date(_out!)} ${_clock(_out!)}'),
                  ),
                ),
                if (_out != null)
                  IconButton(
                    tooltip: 'Clear time-out (still timed in)',
                    onPressed: () => setState(() => _out = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Note (e.g. forgot to time out)', counterText: ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
            ],
          ],
        ),
      ),
      actions: [
        if (!isNew)
          TextButton(
            onPressed: _saving ? null : _delete,
            child: Text('Delete', style: TextStyle(color: AppColors.ledgerRed)),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
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
