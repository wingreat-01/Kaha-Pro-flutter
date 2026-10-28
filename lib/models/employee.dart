/// Payroll employee — separate from AppUser (POS logins), see
/// 20261028_029_employees_timeclock_payroll.sql.
class Employee {
  final String id;
  final String name;
  final String? position;
  final double dailyRate;
  // Scheduled shift as minutes after midnight. shiftEnd <= shiftStart
  // means an overnight shift that ends the next day.
  final int shiftStartMinutes;
  final int shiftEndMinutes;
  final int breakMinutes;
  final int lateGraceMinutes;
  final bool isActive;
  // From employees_with_pin(); a PIN-less employee can't clock in yet.
  final bool hasPin;

  const Employee({
    required this.id,
    required this.name,
    this.position,
    required this.dailyRate,
    this.shiftStartMinutes = 8 * 60,
    this.shiftEndMinutes = 17 * 60,
    this.breakMinutes = 60,
    this.lateGraceMinutes = 0,
    this.isActive = true,
    this.hasPin = false,
  });

  /// Scheduled shift length, crossing midnight when needed.
  int get shiftMinutes {
    final raw = shiftEndMinutes - shiftStartMinutes;
    return raw > 0 ? raw : raw + 24 * 60;
  }

  /// Minutes the daily rate pays for — the shift minus its unpaid break.
  /// Never below 1, so a misconfigured schedule can't divide by zero.
  int get paidMinutes {
    final paid = shiftMinutes - breakMinutes;
    return paid > 0 ? paid : 1;
  }

  factory Employee.fromRow(Map<String, dynamic> row, {bool hasPin = false}) {
    return Employee(
      id: row['id'] as String,
      name: row['name'] as String,
      position: row['position'] as String?,
      dailyRate: (row['daily_rate'] as num).toDouble(),
      shiftStartMinutes: parseTimeOfDay(row['shift_start'] as String?) ?? 8 * 60,
      shiftEndMinutes: parseTimeOfDay(row['shift_end'] as String?) ?? 17 * 60,
      breakMinutes: row['break_minutes'] as int? ?? 60,
      lateGraceMinutes: row['late_grace_minutes'] as int? ?? 0,
      isActive: row['is_active'] as bool? ?? true,
      hasPin: hasPin,
    );
  }

  Map<String, dynamic> toRow() => {
        'name': name.trim(),
        'position': (position == null || position!.trim().isEmpty) ? null : position!.trim(),
        'daily_rate': dailyRate,
        'shift_start': formatTimeOfDay(shiftStartMinutes),
        'shift_end': formatTimeOfDay(shiftEndMinutes),
        'break_minutes': breakMinutes,
        'late_grace_minutes': lateGraceMinutes,
        'is_active': isActive,
      };
}

/// "08:00" / "08:00:00" (Postgres `time`) -> minutes after midnight.
int? parseTimeOfDay(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String formatTimeOfDay(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// "8:00 AM" for display.
String formatClock(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// One time-in / time-out pair. [clockOut] is null while still timed in.
class TimeEntry {
  final String id;
  final String employeeId;
  final DateTime clockIn; // local time
  final DateTime? clockOut;
  final String? inPhotoPath;
  final String? outPhotoPath;
  final String source; // 'clock' | 'manual'
  final bool needsReview;
  final String? note;
  final String? editedBy;

  const TimeEntry({
    required this.id,
    required this.employeeId,
    required this.clockIn,
    this.clockOut,
    this.inPhotoPath,
    this.outPhotoPath,
    this.source = 'clock',
    this.needsReview = false,
    this.note,
    this.editedBy,
  });

  bool get isOpen => clockOut == null;

  int get workedMinutes => clockOut == null ? 0 : clockOut!.difference(clockIn).inMinutes;

  factory TimeEntry.fromRow(Map<String, dynamic> row) {
    return TimeEntry(
      id: row['id'] as String,
      employeeId: row['employee_id'] as String,
      clockIn: DateTime.parse(row['clock_in'] as String).toLocal(),
      clockOut: row['clock_out'] == null ? null : DateTime.parse(row['clock_out'] as String).toLocal(),
      inPhotoPath: row['in_photo_path'] as String?,
      outPhotoPath: row['out_photo_path'] as String?,
      source: row['source'] as String? ?? 'clock',
      needsReview: row['needs_review'] as bool? ?? false,
      note: row['note'] as String?,
      editedBy: row['edited_by'] as String?,
    );
  }
}

/// A manual payslip line — an allowance/bonus (addition) or a cash
/// advance, SSS/PhilHealth/Pag-IBIG share, tax, etc. (deduction).
class PayAdjustment {
  final String label;
  final double amount;
  final bool isDeduction;

  const PayAdjustment({required this.label, required this.amount, required this.isDeduction});

  Map<String, dynamic> toJson() => {
        'label': label,
        'amount': amount,
        'kind': isDeduction ? 'deduction' : 'addition',
      };

  factory PayAdjustment.fromJson(Map<String, dynamic> json) => PayAdjustment(
        label: json['label'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        isDeduction: json['kind'] == 'deduction',
      );
}

/// One employee's computed pay for a period — what a payslip shows.
/// Built by PayrollCalculator, or read back from a saved run.
class PayrollLine {
  final String? employeeId;
  final String employeeName;
  final double dailyRate;
  final int daysWorked;
  final int lateMinutes;
  final int undertimeMinutes;
  final int overtimeMinutes;
  final double basicPay;
  final double overtimePay;
  final double lateDeduction;
  final double undertimeDeduction;
  final List<PayAdjustment> adjustments;
  // Days whose entries need the owner's attention (still timed in, or a
  // missed time-out was auto-closed) — shown as a warning before saving.
  final int daysNeedingReview;

  const PayrollLine({
    this.employeeId,
    required this.employeeName,
    required this.dailyRate,
    required this.daysWorked,
    required this.lateMinutes,
    required this.undertimeMinutes,
    required this.overtimeMinutes,
    required this.basicPay,
    required this.overtimePay,
    required this.lateDeduction,
    required this.undertimeDeduction,
    this.adjustments = const [],
    this.daysNeedingReview = 0,
  });

  double get additions =>
      adjustments.where((a) => !a.isDeduction).fold(0.0, (sum, a) => sum + a.amount);
  double get otherDeductions =>
      adjustments.where((a) => a.isDeduction).fold(0.0, (sum, a) => sum + a.amount);

  double get grossPay => _round(basicPay + overtimePay + additions);
  double get totalDeductions => _round(lateDeduction + undertimeDeduction + otherDeductions);
  double get netPay => _round(grossPay - totalDeductions);

  PayrollLine withAdjustments(List<PayAdjustment> next) => PayrollLine(
        employeeId: employeeId,
        employeeName: employeeName,
        dailyRate: dailyRate,
        daysWorked: daysWorked,
        lateMinutes: lateMinutes,
        undertimeMinutes: undertimeMinutes,
        overtimeMinutes: overtimeMinutes,
        basicPay: basicPay,
        overtimePay: overtimePay,
        lateDeduction: lateDeduction,
        undertimeDeduction: undertimeDeduction,
        adjustments: next,
        daysNeedingReview: daysNeedingReview,
      );

  Map<String, dynamic> toRow(String runId) => {
        'run_id': runId,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'daily_rate': dailyRate,
        'days_worked': daysWorked,
        'late_minutes': lateMinutes,
        'undertime_minutes': undertimeMinutes,
        'overtime_minutes': overtimeMinutes,
        'basic_pay': basicPay,
        'overtime_pay': overtimePay,
        'late_deduction': lateDeduction,
        'undertime_deduction': undertimeDeduction,
        'adjustments': adjustments.map((a) => a.toJson()).toList(),
        'gross_pay': grossPay,
        'total_deductions': totalDeductions,
        'net_pay': netPay,
      };

  factory PayrollLine.fromRow(Map<String, dynamic> row) => PayrollLine(
        employeeId: row['employee_id'] as String?,
        employeeName: row['employee_name'] as String,
        dailyRate: (row['daily_rate'] as num).toDouble(),
        daysWorked: row['days_worked'] as int? ?? 0,
        lateMinutes: row['late_minutes'] as int? ?? 0,
        undertimeMinutes: row['undertime_minutes'] as int? ?? 0,
        overtimeMinutes: row['overtime_minutes'] as int? ?? 0,
        basicPay: (row['basic_pay'] as num).toDouble(),
        overtimePay: (row['overtime_pay'] as num).toDouble(),
        lateDeduction: (row['late_deduction'] as num).toDouble(),
        undertimeDeduction: (row['undertime_deduction'] as num).toDouble(),
        adjustments: ((row['adjustments'] as List?) ?? const [])
            .map((a) => PayAdjustment.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

class PayrollRun {
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool overtimePaid;
  final double totalNet;
  final String? createdBy;
  final DateTime createdAt;

  const PayrollRun({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.overtimePaid,
    required this.totalNet,
    this.createdBy,
    required this.createdAt,
  });

  factory PayrollRun.fromRow(Map<String, dynamic> row) => PayrollRun(
        id: row['id'] as String,
        periodStart: DateTime.parse(row['period_start'] as String),
        periodEnd: DateTime.parse(row['period_end'] as String),
        overtimePaid: row['overtime_paid'] as bool? ?? false,
        totalNet: (row['total_net'] as num).toDouble(),
        createdBy: row['created_by'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
}

double _round(double v) => (v * 100).roundToDouble() / 100;
