import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../models/order_table.dart';
import '../config/qr_ordering_config.dart';
import '../widgets/bounded_content.dart';

/// Shows a table's QR code (Settings → Tables → tap a table) so the
/// owner can save or share it for printing. Encodes
/// QrOrderingConfig.buildOrderUrl(table.qrToken) — scanning it opens
/// order.html, which resolves that token back to this table's store
/// and menu via the get_menu_for_qr RPC (see the QR-ordering
/// migration).
class TableQrScreen extends StatefulWidget {
  final OrderTable table;
  const TableQrScreen({super.key, required this.table});

  @override
  State<TableQrScreen> createState() => _TableQrScreenState();
}

class _TableQrScreenState extends State<TableQrScreen> {
  final _qrKey = GlobalKey();
  bool _sharing = false;

  String get _url => QrOrderingConfig.buildOrderUrl(widget.table.qrToken);

  Future<void> _saveOrShare() async {
    setState(() => _sharing = true);
    try {
      // Capture the white card (QR + label), not just the QR glyphs,
      // so the printed/shared image already has the table name on it.
      final boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final safeLabel = widget.table.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/merq-$safeLabel-qr.png').writeAsBytes(bytes);

      // Share sheet covers both "save to Photos/Files" and "send to
      // printer app" in one action, without needing gallery-write
      // permission plumbing for a first version.
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${widget.table.label} order QR code',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save the QR code: $e', style: AppTextStyles.body(size: 13)),
          backgroundColor: AppColors.ledgerRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text(widget.table.label, style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      body: BoundedContent(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrImageView(
                        data: _url,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.table.label,
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Scan to view the menu and order',
                        style: TextStyle(color: Colors.black54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : _saveOrShare,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ledAmber,
                    foregroundColor: AppColors.charcoal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _sharing
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.charcoal),
                        )
                      : const Icon(Icons.ios_share),
                  label: Text(
                    _sharing ? 'Preparing…' : 'Save or share QR code',
                    style: AppTextStyles.body(size: 14, weight: FontWeight.w700, color: AppColors.charcoal),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _url,
                textAlign: TextAlign.center,
                style: AppTextStyles.mono(size: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
