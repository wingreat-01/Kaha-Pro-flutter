import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import '../models/employee.dart';
import '../services/punch_photo.dart';
import '../state/payroll_provider.dart';
import '../theme/app_theme.dart';

/// Camera needs Android, iOS, or a browser (the web build on a laptop).
/// The Windows/macOS desktop apps have no camera plugin, so they can't
/// take the time-in photo — the screen says so instead of punching
/// without one.
bool get _cameraSupported =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// On-device ML Kit face detection — phones/tablets only. In a browser
/// the photo is still taken and saved, just not checked for a face.
bool get _faceCheckSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

String _clockLabel(DateTime t) => formatClock(t.hour * 60 + t.minute);

/// Shared-device kiosk for time-in / time-out. Reachable from the PIN
/// login screen (no POS login needed) and from Employees & Payroll.
/// Each punch = tap your name → PIN → selfie from the front camera.
class TimeClockScreen extends StatefulWidget {
  const TimeClockScreen({super.key});

  @override
  State<TimeClockScreen> createState() => _TimeClockScreenState();
}

class _TimeClockScreenState extends State<TimeClockScreen> {
  Map<String, DateTime> _openSince = {};
  late final Timer _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final payroll = context.read<PayrollProvider>();
    await payroll.loadEmployees();
    try {
      final open = await payroll.loadOpenEntries();
      if (mounted) setState(() => _openSince = open);
    } catch (e) {
      debugPrint('loadOpenEntries failed: $e');
    }
  }

  Future<void> _open(Employee employee) async {
    if (!employee.hasPin) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${employee.name} has no PIN yet. Ask your admin to set one in Employees & Payroll.'),
      ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PunchScreen(employee: employee, isTimeIn: !_openSince.containsKey(employee.id)),
    ));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final payroll = context.watch<PayrollProvider>();
    final employees = payroll.activeEmployees;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('Time Clock', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                Text(
                  _clockLabel(_now),
                  style: AppTextStyles.mono(size: 34, weight: FontWeight.w700, color: AppColors.ledAmber),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap your name to time in or out. A photo is taken with each punch for attendance records.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (!_cameraSupported)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'This device has no supported camera. Use the time clock on a phone, tablet, or the web version in a browser.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed),
              ),
            ),
          Expanded(
            child: payroll.loading && employees.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : employees.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            payroll.error ?? 'No employees yet. An admin can add them in Settings → Employees & Payroll.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.5,
                        ),
                        itemCount: employees.length,
                        itemBuilder: (context, i) {
                          final e = employees[i];
                          final since = _openSince[e.id];
                          return _EmployeeTile(
                            employee: e,
                            inSince: since,
                            onTap: _cameraSupported ? () => _open(e) : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final Employee employee;
  final DateTime? inSince;
  final VoidCallback? onTap;

  const _EmployeeTile({required this.employee, this.inSince, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIn = inSince != null;
    return Material(
      color: AppColors.slate,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isIn ? AppColors.tillGreen : AppColors.slateBorder, width: isIn ? 1.5 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                employee.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(size: 15, weight: FontWeight.w700),
              ),
              if (employee.position != null) ...[
                const SizedBox(height: 2),
                Text(employee.position!, style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
              ],
              const SizedBox(height: 6),
              Text(
                isIn ? 'IN since ${_clockLabel(inSince!)}' : 'OUT',
                style: AppTextStyles.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: isIn ? AppColors.tillGreen : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Camera + PIN for one employee. The camera is only switched on here
/// (not on the list screen), so it isn't running while the kiosk sits idle.
class _PunchScreen extends StatefulWidget {
  final Employee employee;
  final bool isTimeIn;

  const _PunchScreen({required this.employee, required this.isTimeIn});

  @override
  State<_PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<_PunchScreen> {
  final _pinCtrl = TextEditingController();
  CameraController? _camera;
  FaceDetector? _faceDetector;
  String? _cameraError;
  String? _error;
  bool _busy = false;
  PunchResult? _result;
  Uint8List? _resultPhoto;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    if (_faceCheckSupported) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, minFaceSize: 0.15),
      );
    }
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera found on this device.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first, // laptops often report "external"
      );
      final controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } on CameraException catch (e) {
      debugPrint('camera init failed: ${e.code} ${e.description}');
      setState(() => _cameraError = e.code.contains('Denied') || e.code.contains('denied')
          ? 'Camera permission is off. Allow camera access to use the time clock.'
          : 'Could not start the camera.');
    } catch (e) {
      debugPrint('camera init failed: $e');
      setState(() => _cameraError = 'Could not start the camera.');
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _camera?.dispose();
    _faceDetector?.close();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();

      final detector = _faceDetector;
      if (detector != null) {
        final faces = await detector.processImage(InputImage.fromFilePath(shot.path));
        if (faces.isEmpty) {
          _fail('No face detected. Look straight at the camera and try again.');
          return;
        }
        if (faces.length > 1) {
          _fail('More than one face in the photo. Only the employee should be in frame.');
          return;
        }
      }

      // Face check above ran on the full-size shot; only a small copy is
      // stored (see punch_photo.dart).
      final small = await shrinkPunchPhoto(bytes);
      if (!mounted) return;
      final result = await context.read<PayrollProvider>().punch(widget.employee, pin, small);
      if (!mounted) return;
      if (!result.ok) {
        _fail(result.error ?? 'Could not record the punch.');
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        _result = result;
        _resultPhoto = small;
      });
      _closeTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (e) {
      debugPrint('punch failed: $e');
      _fail('Something went wrong. Try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    _pinCtrl.clear();
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text(widget.employee.name, style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: result != null ? _buildResult(result) : _buildCapture(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapture() {
    final camera = _camera;
    final label = widget.isTimeIn ? 'TIME IN' : 'TIME OUT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              color: Colors.black,
              child: _cameraError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_cameraError!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body(size: 13, color: Colors.white70)),
                      ),
                    )
                  : camera == null || !camera.value.isInitialized
                      ? const Center(child: CircularProgressIndicator())
                      : FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: camera.value.previewSize?.height ?? 300,
                            height: camera.value.previewSize?.width ?? 400,
                            child: CameraPreview(camera),
                          ),
                        ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Center your face in the frame.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pinCtrl,
          enabled: !_busy,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 8,
          textAlign: TextAlign.center,
          style: AppTextStyles.mono(size: 22, weight: FontWeight.w700, letterSpacing: 6),
          decoration: const InputDecoration(hintText: 'PIN', counterText: ''),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.isTimeIn ? AppColors.tillGreen : AppColors.ledAmber,
              foregroundColor: AppColors.charcoal,
            ),
            onPressed: _busy || camera == null ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(label, style: AppTextStyles.mono(size: 16, weight: FontWeight.w700, color: AppColors.charcoal)),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(PunchResult result) {
    final color = result.isTimeIn ? AppColors.tillGreen : AppColors.ledAmber;
    return Column(
      children: [
        if (_resultPhoto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(80),
            child: Image.memory(_resultPhoto!, width: 140, height: 140, fit: BoxFit.cover),
          ),
        const SizedBox(height: 16),
        Icon(Icons.check_circle, color: color, size: 48),
        const SizedBox(height: 8),
        Text(
          result.isTimeIn ? 'TIMED IN' : 'TIMED OUT',
          style: AppTextStyles.mono(size: 22, weight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          '${result.employeeName ?? widget.employee.name} · ${_clockLabel(result.at!)}',
          style: AppTextStyles.body(size: 16, weight: FontWeight.w600),
        ),
        if (result.closedMissedOut) ...[
          const SizedBox(height: 12),
          Text(
            'Your last time-out was missing, so it was flagged for your admin to fix.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(size: 12.5, color: AppColors.ledAmber),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
