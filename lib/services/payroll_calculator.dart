import '../models/employee.dart';

/// Daily-rate payroll math. Pure (no I/O) so it can be unit-tested — see
/// test/payroll_calculator_test.dart.
///
/// Per day an employee has at least one completed time entry:
///  * pay = daily rate (one day, regardless of how many punches)
///  * late = first time-in after shift start, if beyond the grace period
///    (past the grace, the whole lateness counts — not just the excess)
///  * undertime = last time-out before shift end
///  * overtime = last time-out after shift end — only paid when the run
///    says so, at [overtimeMultiplier] × the per-minute rate
/// The per-minute rate is daily rate ÷ paid shift minutes (shift minus
/// break). Late + undertime are capped at a full day, so a short day
/// never goes below zero.
///
/// Entries still timed in, and auto-closed missed time-outs (zero
/// length, needs_review), don't count as worked — they're reported in
/// [PayrollLine.daysNeedingReview] so the owner fixes them first.
class PayrollCalculator {
  PayrollCalculator._();

  static PayrollLine compute(
    Employee employee,
    List<TimeEntry> entries, {
    required DateTime from,
    required DateTime to,
    bool payOvertime = false,
    double overtimeMultiplier = 1.25,
  }) {
    final first = _dateOnly(from);
    final last = _dateOnly(to);

    final byDay = <DateTime, List<TimeEntry>>{};
    for (final e in entries) {
      if (e.employeeId != employee.id) continue;
      final day = workDayOf(employee, e.clockIn);
      if (day.isBefore(first) || day.isAfter(last)) continue;
      byDay.putIfAbsent(day, () => []).add(e);
    }

    final perMinute = employee.dailyRate / employee.paidMinutes;
    var days = 0, late = 0, under = 0, over = 0, review = 0;

    for (final entry in byDay.entries) {
      final day = entry.key;
      final list = entry.value;
      final completed = list.where((e) => !e.isOpen && e.workedMinutes > 0).toList();
      if (list.any((e) => e.isOpen || e.needsReview)) review++;
      if (completed.isEmpty) continue;

      days++;
      final start = day.add(Duration(minutes: employee.shiftStartMinutes));
      final end = start.add(Duration(minutes: employee.shiftMinutes));
      final firstIn = completed.map((e) => e.clockIn).reduce((a, b) => a.isBefore(b) ? a : b);
      final lastOut = completed.map((e) => e.clockOut!).reduce((a, b) => a.isAfter(b) ? a : b);

      var dayLate = firstIn.difference(start).inMinutes;
      dayLate = dayLate > employee.lateGraceMinutes ? dayLate : 0;
      var dayUnder = end.difference(lastOut).inMinutes;
      dayUnder = dayUnder > 0 ? dayUnder : 0;
      final dayOver = lastOut.difference(end).inMinutes;

      // A day can't cost more than it pays.
      if (dayLate + dayUnder > employee.paidMinutes) {
        dayLate = dayLate > employee.paidMinutes ? employee.paidMinutes : dayLate;
        dayUnder = employee.paidMinutes - dayLate;
      }

      late += dayLate;
      under += dayUnder;
      if (dayOver > 0) over += dayOver;
    }

    return PayrollLine(
      employeeId: employee.id,
      employeeName: employee.name,
      dailyRate: employee.dailyRate,
      daysWorked: days,
      lateMinutes: late,
      undertimeMinutes: under,
      overtimeMinutes: over,
      basicPay: _money(days * employee.dailyRate),
      overtimePay: payOvertime ? _money(over * perMinute * overtimeMultiplier) : 0,
      lateDeduction: _money(late * perMinute),
      undertimeDeduction: _money(under * perMinute),
      daysNeedingReview: review,
    );
  }

  /// The work day a punch belongs to. Normally its calendar date; for an
  /// overnight shift (e.g. 10 PM–6 AM), a time-in after midnight but
  /// before the shift ends counts toward the shift that began the
  /// previous evening.
  static DateTime workDayOf(Employee employee, DateTime clockIn) {
    final day = _dateOnly(clockIn);
    final overnight = employee.shiftEndMinutes <= employee.shiftStartMinutes;
    final minuteOfDay = clockIn.hour * 60 + clockIn.minute;
    if (overnight && minuteOfDay < employee.shiftEndMinutes) {
      return DateTime(day.year, day.month, day.day - 1);
    }
    return day;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static double _money(double v) => (v * 100).roundToDouble() / 100;
}
