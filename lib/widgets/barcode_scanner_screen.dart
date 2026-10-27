import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

/// What the camera screen shows after a code was handled in
/// continuous mode (see [BarcodeScannerScreen.scanContinuously]).
class ScanFeedback {
  final bool ok;
  final String message;

  /// Optional button on the feedback chip, e.g. "Add product" when a
  /// scanned code isn't in the catalog. Tapping it closes the scanner
  /// and then runs [onAction].
  final String? actionLabel;
  final VoidCallback? onAction;

  const ScanFeedback.ok(this.message)
      : ok = true,
        actionLabel = null,
        onAction = null;

  const ScanFeedback.fail(this.message, {this.actionLabel, this.onAction}) : ok = false;
}

/// Full-screen camera barcode scanner (Android, iOS and web).
///
/// Two modes:
///  - [scanOnce]: returns the first code it reads (used by the Barcode
///    field in the add-product dialog).
///  - [scanContinuously]: stays open after each scan, hands the code to
///    [onScan], shows the returned [ScanFeedback], and keeps going so a
///    cashier can scan a whole basket (used by Register).
class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  final Future<ScanFeedback> Function(BuildContext context, String code)? onScan;

  const BarcodeScannerScreen({super.key, this.title = 'Scan barcode', this.onScan});

  static Future<String?> scanOnce(BuildContext context, {String title = 'Scan barcode'}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BarcodeScannerScreen(title: title),
      ),
    );
  }

  static Future<void> scanContinuously(
    BuildContext context, {
    String title = 'Scan items',
    required Future<ScanFeedback> Function(BuildContext context, String code) onScan,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BarcodeScannerScreen(title: title, onScan: onScan),
      ),
    );
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  // Retail symbologies only — a short list decodes faster and avoids
  // stray reads of unrelated codes.
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
  );

  static const Duration _sameCodeCooldown = Duration(milliseconds: 1500);

  bool _busy = false;
  String? _lastCode;
  DateTime? _lastAt;
  ScanFeedback? _feedback;
  Timer? _feedbackTimer;
  int _okCount = 0;

  bool get _continuous => widget.onScan != null;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;

    String? code;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        code = v;
        break;
      }
    }
    if (code == null) return;

    final now = DateTime.now();
    if (code == _lastCode && _lastAt != null && now.difference(_lastAt!) < _sameCodeCooldown) {
      return; // same barcode still in view — don't ring it up twice
    }

    _busy = true;
    _lastCode = code;
    _lastAt = now;

    try {
      if (!_continuous) {
        HapticFeedback.mediumImpact();
        if (mounted) Navigator.of(context).pop(code);
        return;
      }

      final feedback = await widget.onScan!(context, code);
      if (!mounted) return;
      if (feedback.ok) {
        HapticFeedback.mediumImpact();
        _okCount += 1;
      } else {
        HapticFeedback.heavyImpact();
      }
      _lastAt = DateTime.now(); // cooldown counts from when handling finished
      setState(() => _feedback = feedback);
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _feedback = null);
      });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedback = _feedback;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        title: Text(widget.title, style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () async {
              try {
                await _controller.toggleTorch();
              } catch (_) {/* device has no torch */}
            },
          ),
          if (_continuous)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _okCount > 0 ? 'Done ($_okCount)' : 'Done',
                style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber),
              ),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.ledAmber, width: 2.5),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (feedback != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.slate,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: feedback.ok ? AppColors.tillGreen : AppColors.ledgerRed,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            feedback.ok ? Icons.check_circle_outline : Icons.error_outline,
                            size: 18,
                            color: feedback.ok ? AppColors.tillGreen : AppColors.ledgerRed,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(feedback.message, style: AppTextStyles.body(size: 13)),
                          ),
                          if (feedback.actionLabel != null && feedback.onAction != null)
                            TextButton(
                              onPressed: () {
                                final action = feedback.onAction!;
                                Navigator.of(context).pop();
                                action();
                              },
                              child: Text(
                                feedback.actionLabel!,
                                style: AppTextStyles.body(
                                    size: 12, weight: FontWeight.w700, color: AppColors.ledAmber),
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _continuous
                            ? 'Point at an item\'s barcode — each scan is added to the cart'
                            : 'Point the camera at the barcode',
                        style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
