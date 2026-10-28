import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';
import '../services/payroll_calculator.dart';

/// Result of a time clock punch — see clock_punch() in
/// 20261028_029_employees_timeclock_payroll.sql.
class PunchResult {
  final bool ok;
  final bool isTimeIn;
  final DateTime? at;
  final String? employeeName;
  final String? error;
  // A forgotten time-out from an earlier shift was auto-closed and
  // flagged for the owner to fix.
  final bool closedMissedOut;

  const PunchResult.success({
    required this.isTimeIn,
    required this.at,
    required this.employeeName,
    this.closedMissedOut = false,
  })  : ok = true,
        error = null;

  const PunchResult.failure(this.error)
      : ok = false,
        isTimeIn = false,
        at = null,
        employeeName = null,
        closedMissedOut = false;
}

/// Employees, time clock and payroll. Everything here needs to be online:
/// a punch is stamped with the server's clock, so it can't be queued.
class PayrollProvider extends ChangeNotifier {
  static const photoBucket = 'timeclock-photos';

  final SupabaseClient _client = Supabase.instance.client;

  List<Employee> _employees = [];
  bool _loading = false;
  String? _error;

  /// Active and inactive, sorted by name. Use [activeEmployees] for the
  /// time clock.
  List<Employee> get employees => List.unmodifiable(_employees);
  List<Employee> get activeEmployees => _employees.where((e) => e.isActive).toList();
  bool get loading => _loading;
  String? get error => _error;

  // ---------------------------------------------------------------------
  // Employees
  // ---------------------------------------------------------------------

  Future<void> loadEmployees() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await _client.from('employees').select().order('name');
      Set<String> withPin = {};
      try {
        final pins = await _client.rpc('employees_with_pin') as List;
        withPin = pins.map((p) => p is Map ? p.values.first as String : p as String).toSet();
      } catch (e) {
        debugPrint('employees_with_pin failed: $e');
      }
      _employees = (rows as List)
          .map((r) => Employee.fromRow(r as Map<String, dynamic>, hasPin: withPin.contains(r['id'])))
          .toList();
    } catch (e) {
      debugPrint('loadEmployees failed: $e');
      _error = 'Could not load employees. Check your connection.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Creates or updates [employee] (id empty = new), then sets [pin] when
  /// given. Returns the saved employee's id.
  Future<String> saveEmployee(Employee employee, {String? pin}) async {
    final String id;
    try {
      if (employee.id.isEmpty) {
        final row = await _client.from('employees').insert(employee.toRow()).select('id').single();
        id = row['id'] as String;
      } else {
        await _client.from('employees').update(employee.toRow()).eq('id', employee.id);
        id = employee.id;
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw StateError('An employee with that name already exists.');
      rethrow;
    }
    if (pin != null && pin.isNotEmpty) {
      await _client.rpc('set_employee_pin', params: {'p_employee_id': id, 'p_pin': pin});
    }
    await loadEmployees();
    return id;
  }

  // ---------------------------------------------------------------------
  // Time clock
  // ---------------------------------------------------------------------

  /// Uploads the selfie, then punches. A wrong PIN (or any refusal) removes
  /// the just-uploaded photo again, so rejected attempts don't pile up.
  Future<PunchResult> punch(Employee employee, String pin, Uint8List photo) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const PunchResult.failure('This device is signed out of the store.');

    final path = '$uid/${employee.id}/${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}.jpg';
    try {
      await _client.storage.from(photoBucket).uploadBinary(
            path,
            photo,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    } catch (e) {
      debugPrint('time clock photo upload failed: $e');
      return const PunchResult.failure('Could not save the photo. Check your connection and try again.');
    }

    Map<String, dynamic> result;
    try {
      result = await _client.rpc('clock_punch', params: {
        'p_employee_id': employee.id,
        'p_pin': pin,
        'p_photo_path': path,
      });
    } catch (e) {
      debugPrint('clock_punch failed: $e');
      _removePhoto(path);
      return const PunchResult.failure('Could not record the punch. Check your connection and try again.');
    }

    if (result['ok'] != true) {
      _removePhoto(path);
      return PunchResult.failure(result['error'] as String? ?? 'Could not record the punch.');
    }
    return PunchResult.success(
      isTimeIn: result['action'] == 'in',
      at: DateTime.parse(result['at'] as String).toLocal(),
      employeeName: result['employee_name'] as String?,
      closedMissedOut: result['closed_missed_out'] == true,
    );
  }

  void _removePhoto(String path) {
    _client.storage.from(photoBucket).remove([path]).catchError((Object e) {
      debugPrint('could not remove rejected punch photo $path: $e');
      return <FileObject>[];
    });
  }

  static String _randomSuffix() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Employee ids currently timed in — for the "IN since 8:02" badges.
  Future<Map<String, DateTime>> loadOpenEntries() async {
    final rows = await _client
        .from('time_entries')
        .select('employee_id, clock_in')
        .isFilter('clock_out', null);
    return {
      for (final r in rows as List)
        r['employee_id'] as String: DateTime.parse(r['clock_in'] as String).toLocal(),
    };
  }

  /// Short-lived link for viewing a punch photo (the bucket is private).
  Future<String?> photoUrl(String path) async {
    try {
      return await _client.storage.from(photoBucket).createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('signed url failed for $path: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Time records
  // ---------------------------------------------------------------------

  /// Entries whose time-in falls in [from]..[to] (dates, inclusive), newest
  /// first. Starts a day early so an overnight shift's after-midnight
  /// punches are included.
  Future<List<TimeEntry>> loadEntries(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day - 1);
    final end = DateTime(to.year, to.month, to.day + 1);
    final rows = await _client
        .from('time_entries')
        .select()
        .gte('clock_in', start.toUtc().toIso8601String())
        .lt('clock_in', end.toUtc().toIso8601String())
        .order('clock_in', ascending: false);
    return (rows as List).map((r) => TimeEntry.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// Owner correction (or a manual entry when [id] is null). Clears the
  /// review flag — the owner has now looked at it.
  Future<void> saveEntry({
    String? id,
    required String employeeId,
    required DateTime clockIn,
    DateTime? clockOut,
    String? note,
    required String editedBy,
  }) async {
    final data = {
      'employee_id': employeeId,
      'clock_in': clockIn.toUtc().toIso8601String(),
      'clock_out': clockOut?.toUtc().toIso8601String(),
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'edited_by': editedBy,
      'needs_review': false,
    };
    if (id == null) {
      await _client.from('time_entries').insert({...data, 'source': 'manual'});
    } else {
      await _client.from('time_entries').update(data).eq('id', id);
    }
  }

  Future<void> deleteEntry(TimeEntry entry) async {
    await _client.from('time_entries').delete().eq('id', entry.id);
    final photos = [entry.inPhotoPath, entry.outPhotoPath].whereType<String>().toList();
    if (photos.isNotEmpty) {
      try {
        await _client.storage.from(photoBucket).remove(photos);
      } catch (e) {
        debugPrint('could not remove photos for deleted entry ${entry.id}: $e');
      }
    }
  }

  // ---------------------------------------------------------------------
  // Payroll
  // ---------------------------------------------------------------------

  /// One line per active employee for the period, plus any inactive one
  /// who still has time in it (left mid-period, still owed pay).
  Future<List<PayrollLine>> computePayroll(
    DateTime from,
    DateTime to, {
    required bool payOvertime,
    required double overtimeMultiplier,
  }) async {
    if (_employees.isEmpty) await loadEmployees();
    final entries = await loadEntries(from, to);
    final withTime = entries.map((e) => e.employeeId).toSet();
    return _employees
        .where((e) => e.isActive || withTime.contains(e.id))
        .map((e) => PayrollCalculator.compute(
              e,
              entries,
              from: from,
              to: to,
              payOvertime: payOvertime,
              overtimeMultiplier: overtimeMultiplier,
            ))
        .toList();
  }

  Future<String> saveRun({
    required DateTime from,
    required DateTime to,
    required bool payOvertime,
    required double overtimeMultiplier,
    required List<PayrollLine> lines,
    required String createdBy,
  }) async {
    final run = await _client
        .from('payroll_runs')
        .insert({
          'period_start': _date(from),
          'period_end': _date(to),
          'overtime_paid': payOvertime,
          'overtime_multiplier': overtimeMultiplier,
          'total_net': lines.fold(0.0, (sum, l) => sum + l.netPay),
          'created_by': createdBy,
        })
        .select('id')
        .single();
    final runId = run['id'] as String;
    try {
      await _client.from('payroll_items').insert(lines.map((l) => l.toRow(runId)).toList());
    } catch (e) {
      // Don't leave a run with no payslips behind.
      await _client.from('payroll_runs').delete().eq('id', runId);
      rethrow;
    }
    return runId;
  }

  Future<List<PayrollRun>> loadRuns() async {
    final rows = await _client.from('payroll_runs').select().order('created_at', ascending: false).limit(100);
    return (rows as List).map((r) => PayrollRun.fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<List<PayrollLine>> loadRunLines(String runId) async {
    final rows = await _client.from('payroll_items').select().eq('run_id', runId).order('employee_name');
    return (rows as List).map((r) => PayrollLine.fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<void> deleteRun(String runId) async {
    await _client.from('payroll_runs').delete().eq('id', runId);
  }

  // ---------------------------------------------------------------------
  // Photo retention
  // ---------------------------------------------------------------------
  //
  // Selfies are only needed to settle "was it really them?" for recent
  // pay periods, so they're deleted after [photoRetentionDays]; the time
  // records themselves are kept forever. Deletion has to go through the
  // Storage API (deleting storage.objects rows in SQL leaves the files
  // behind), so it runs from the app: whenever an admin opens Employees &
  // Payroll, at most once a day per device.

  static const retentionChoices = [30, 60, 90, 180];
  static const _retentionKey = 'timeclock_photo_retention_days';
  static const _lastPurgeKey = 'timeclock_photo_last_purge';

  int _photoRetentionDays = 90;
  int get photoRetentionDays => _photoRetentionDays;

  /// Photos taken before this are deleted by [purgeOldPhotos].
  DateTime get photoCutoff {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - _photoRetentionDays);
  }

  Future<void> loadPhotoSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_retentionKey);
      if (saved != null && retentionChoices.contains(saved) && saved != _photoRetentionDays) {
        _photoRetentionDays = saved;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable — keep the default.
    }
  }

  /// Saves the new period and purges right away, so a shorter period
  /// takes effect immediately.
  Future<int> setPhotoRetentionDays(int days) async {
    if (!retentionChoices.contains(days)) return 0;
    _photoRetentionDays = days;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_retentionKey, days);
    } catch (_) {}
    return purgeOldPhotos(force: true);
  }

  /// Deletes punch photos older than the retention period and clears their
  /// paths on the time records. Returns how many photos were removed.
  /// Never throws — cleanup failing must not get in the owner's way; it
  /// simply tries again next time.
  Future<int> purgeOldPhotos({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayKey = today.year * 10000 + today.month * 100 + today.day;
      if (!force && prefs.getInt(_lastPurgeKey) == todayKey) return 0;

      final cutoff = photoCutoff.toUtc().toIso8601String();
      var removed = 0;
      // Batches of 200; capped so one visit never spins for long — the
      // rest goes on the next run.
      for (var batch = 0; batch < 25; batch++) {
        final rows = await _client
            .from('time_entries')
            .select('id, in_photo_path, out_photo_path')
            .lt('clock_in', cutoff)
            .or('in_photo_path.not.is.null,out_photo_path.not.is.null')
            .limit(200) as List;
        if (rows.isEmpty) break;

        final ids = <String>[];
        final paths = <String>[];
        for (final r in rows) {
          ids.add(r['id'] as String);
          for (final key in ['in_photo_path', 'out_photo_path']) {
            final p = r[key] as String?;
            if (p != null) paths.add(p);
          }
        }
        // Files first: if clearing the paths then fails, the next run
        // just re-removes files that are already gone, which is harmless.
        if (paths.isNotEmpty) await _client.storage.from(photoBucket).remove(paths);
        await _client
            .from('time_entries')
            .update({'in_photo_path': null, 'out_photo_path': null})
            .inFilter('id', ids);
        removed += paths.length;
        if (rows.length < 200) break;
      }

      await prefs.setInt(_lastPurgeKey, todayKey);
      if (removed > 0) debugPrint('Purged $removed time clock photos older than $_photoRetentionDays days');
      return removed;
    } catch (e) {
      debugPrint('purgeOldPhotos failed (will retry next time): $e');
      return 0;
    }
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
