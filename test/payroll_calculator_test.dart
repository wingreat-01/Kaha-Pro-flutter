import 'package:flutter_test/flutter_test.dart';
import 'package:kahapro_flutter/models/employee.dart';
import 'package:kahapro_flutter/services/payroll_calculator.dart';

// 8:00–17:00 with a 60-min break = 480 paid minutes, so ₱480/day makes
// the per-minute rate exactly ₱1.00 and the expected amounts easy to read.
const emp = Employee(id: 'e1', name: 'Juan', dailyRate: 480);

TimeEntry entry(DateTime inAt, DateTime? outAt, {bool review = false, String employeeId = 'e1'}) =>
    TimeEntry(id: inAt.toIso8601String(), employeeId: employeeId, clockIn: inAt, clockOut: outAt, needsReview: review);

PayrollLine run(List<TimeEntry> entries, {bool ot = false, Employee e = emp}) => PayrollCalculator.compute(
      e,
      entries,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 15),
      payOvertime: ot,
    );

void main() {
  test('on-time full days pay the daily rate, no deductions', () {
    final line = run([
      entry(DateTime(2026, 10, 1, 7, 55), DateTime(2026, 10, 1, 17, 0)),
      entry(DateTime(2026, 10, 2, 8, 0), DateTime(2026, 10, 2, 17, 5)),
    ]);
    expect(line.daysWorked, 2);
    expect(line.basicPay, 960);
    expect(line.lateMinutes, 0);
    expect(line.undertimeMinutes, 0);
    expect(line.netPay, 960);
  });

  test('late and undertime are deducted per minute', () {
    final line = run([entry(DateTime(2026, 10, 1, 8, 15), DateTime(2026, 10, 1, 16, 30))]);
    expect(line.lateMinutes, 15);
    expect(line.undertimeMinutes, 30);
    expect(line.lateDeduction, 15);
    expect(line.undertimeDeduction, 30);
    expect(line.netPay, 435);
  });

  test('grace period forgives small lateness, but not beyond it', () {
    const graced = Employee(id: 'e1', name: 'Juan', dailyRate: 480, lateGraceMinutes: 10);
    expect(run([entry(DateTime(2026, 10, 1, 8, 9), DateTime(2026, 10, 1, 17, 0))], e: graced).lateMinutes, 0);
    expect(run([entry(DateTime(2026, 10, 1, 8, 12), DateTime(2026, 10, 1, 17, 0))], e: graced).lateMinutes, 12);
  });

  test('lunch out/in on the same day counts as one day, first in / last out', () {
    final line = run([
      entry(DateTime(2026, 10, 1, 8, 0), DateTime(2026, 10, 1, 12, 0)),
      entry(DateTime(2026, 10, 1, 13, 0), DateTime(2026, 10, 1, 17, 0)),
    ]);
    expect(line.daysWorked, 1);
    expect(line.basicPay, 480);
    expect(line.undertimeMinutes, 0);
  });

  test('overtime is only paid when the run includes it', () {
    final entries = [entry(DateTime(2026, 10, 1, 8, 0), DateTime(2026, 10, 1, 19, 0))];
    final unpaid = run(entries);
    expect(unpaid.overtimeMinutes, 120);
    expect(unpaid.overtimePay, 0);
    final paid = run(entries, ot: true);
    expect(paid.overtimePay, 150); // 120 min × ₱1 × 1.25
  });

  test('open and missed-time-out entries are flagged, not paid', () {
    final line = run([
      entry(DateTime(2026, 10, 1, 8, 0), null),
      entry(DateTime(2026, 10, 2, 8, 0), DateTime(2026, 10, 2, 8, 0), review: true),
    ]);
    expect(line.daysWorked, 0);
    expect(line.daysNeedingReview, 2);
  });

  test('entries outside the period or for other employees are ignored', () {
    final line = run([
      entry(DateTime(2026, 9, 30, 8, 0), DateTime(2026, 9, 30, 17, 0)),
      entry(DateTime(2026, 10, 16, 8, 0), DateTime(2026, 10, 16, 17, 0)),
      entry(DateTime(2026, 10, 3, 8, 0), DateTime(2026, 10, 3, 17, 0), employeeId: 'other'),
    ]);
    expect(line.daysWorked, 0);
  });

  test('a very short day never deducts more than the day pays', () {
    final line = run([entry(DateTime(2026, 10, 1, 16, 50), DateTime(2026, 10, 1, 16, 55))]);
    expect(line.lateDeduction + line.undertimeDeduction, lessThanOrEqualTo(480));
    expect(line.netPay, greaterThanOrEqualTo(0));
  });

  test('overnight shift: after-midnight time-in belongs to the previous evening', () {
    const night = Employee(
      id: 'e1', name: 'Ana', dailyRate: 480,
      shiftStartMinutes: 22 * 60, shiftEndMinutes: 6 * 60, breakMinutes: 0,
    );
    final line = run([entry(DateTime(2026, 10, 2, 0, 30), DateTime(2026, 10, 2, 6, 0))], e: night);
    expect(line.daysWorked, 1);
    expect(line.lateMinutes, 150); // shift began 10 PM on Oct 1
    expect(line.undertimeMinutes, 0);
  });

  test('manual adjustments flow into gross, deductions and net', () {
    final line = run([entry(DateTime(2026, 10, 1, 8, 0), DateTime(2026, 10, 1, 17, 0))]).withAdjustments(const [
      PayAdjustment(label: 'Allowance', amount: 100, isDeduction: false),
      PayAdjustment(label: 'Cash advance', amount: 200, isDeduction: true),
    ]);
    expect(line.grossPay, 580);
    expect(line.totalDeductions, 200);
    expect(line.netPay, 380);
  });
}
