import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../state/store_provider.dart';
import '../widgets/bounded_content.dart';

/// Settings → QR Order Payments — which payment options customers see
/// on the QR ordering page:
///   • Pay at the counter (default, no setup)
///   • Pay online — the store uploads its own GCash / Maya / bank QR;
///     the customer pays in their own e-wallet and types the reference
///     number, and the cashier verifies it on the Incoming Orders
///     screen. No payment gateway is involved, so the app can't
///     confirm the money arrived; the cashier always does.
///
/// Toggles and the instructions text are saved with the Save button;
/// uploading or removing the QR image takes effect immediately.
///
/// Error snackbars include the real exception text (and the full
/// error + stack trace go to the debug console) so a failing upload
/// can be diagnosed instead of showing a generic message.
class QrPaymentsPanel extends StatefulWidget {
  const QrPaymentsPanel({super.key});

  @override
  State<QrPaymentsPanel> createState() => _QrPaymentsPanelState();
}

class _QrPaymentsPanelState extends State<QrPaymentsPanel> {
  late bool _counter;
  late bool _online;
  late final TextEditingController _instructionsCtrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<StoreProvider>().store;
    _counter = store?.qrPayCounterEnabled ?? true;
    _online = store?.qrPayOnlineEnabled ?? false;
    _instructionsCtrl = TextEditingController(text: store?.onlinePaymentInstructions ?? '');
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.body(size: 13, color: Colors.white, weight: FontWeight.w600),
        ),
        // Explicit colors on both states: the theme's default snackbar
        // background is light in dark mode, which made the gray body
        // text unreadable.
        backgroundColor: error ? AppColors.ledgerRed : const Color(0xFF2E7D32),
        duration: Duration(seconds: error ? 8 : 4),
      ),
    );
  }

  void _onCounterChanged(bool value) {
    if (!value && !_online) {
      _snack('Keep at least one payment option turned on.');
      return;
    }
    setState(() => _counter = value);
  }

  void _onOnlineChanged(bool value, bool hasQr) {
    if (value && !hasQr) {
      _snack('Upload your payment QR first.');
      return;
    }
    if (!value && !_counter) {
      _snack('Keep at least one payment option turned on.');
      return;
    }
    setState(() => _online = value);
  }

  Future<void> _pickQr() async {
    final provider = context.read<StoreProvider>();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 90,
      );
      if (picked == null) return;
      if (mounted) setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      await provider.uploadOnlinePaymentQr(bytes);
      _snack('Payment QR saved.');
    } catch (e, st) {
      debugPrint('QR UPLOAD ERROR: $e\n$st');
      _snack('Could not upload the QR: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeQr() async {
    final provider = context.read<StoreProvider>();
    setState(() => _uploading = true);
    try {
      await provider.removeOnlinePaymentQr();
      if (mounted) setState(() => _online = false);
    } catch (e, st) {
      debugPrint('QR REMOVE ERROR: $e\n$st');
      _snack('Could not remove the QR: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final provider = context.read<StoreProvider>();
    final text = _instructionsCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await provider.updateQrPayments(
        counterEnabled: _counter,
        onlineEnabled: _online,
        instructions: text.isEmpty ? null : text,
      );
      _snack('Saved.');
    } catch (e, st) {
      debugPrint('QR PAYMENTS SAVE ERROR: $e\n$st');
      _snack('Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreProvider>().store;
    final qrUrl = store?.onlinePaymentQrUrl;
    final hasQr = qrUrl != null && qrUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('QR Order Payments', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 2, right: 2),
              child: Text(
                'Choose how customers can pay when they order from a table QR code. If both are on, they pick one before placing the order.',
                style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
              ),
            ),
            _card(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pay at the counter', style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          'Customer pays the cashier when done',
                          style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: _counter, onChanged: _onCounterChanged, activeColor: AppColors.tillGreen),
                ],
              ),
            ),
            _card(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pay online', style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          hasQr ? 'Customer pays your QR, then enters the reference' : 'Upload your payment QR below to turn this on',
                          style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _online,
                    onChanged: (v) => _onOnlineChanged(v, hasQr),
                    activeColor: AppColors.tillGreen,
                  ),
                ],
              ),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your payment QR', style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Your GCash, Maya or bank QR Ph image. Customers see it after choosing to pay online.',
                    style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (hasQr)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: Colors.white,
                          child: Image.network(
                            qrUrl,
                            height: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => SizedBox(
                              height: 120,
                              child: Center(
                                child: Text('Could not show the image', style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (hasQr) const SizedBox(height: 12),
                  if (_uploading)
                    const Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickQr,
                          icon: const Icon(Icons.upload_outlined, size: 18),
                          label: Text(hasQr ? 'Replace QR' : 'Upload QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ledAmber,
                            side: BorderSide(color: AppColors.ledAmber),
                          ),
                        ),
                        if (hasQr)
                          TextButton(
                            onPressed: _removeQr,
                            child: Text('Remove', style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Instructions (optional)', style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Shown under the QR, for example the account name to look for.',
                    style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _instructionsCtrl,
                    maxLines: 3,
                    maxLength: 200,
                    style: AppTextStyles.body(size: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Send to "Sunrise Café" on GCash, then enter the reference number.',
                      hintStyle: AppTextStyles.body(size: 13, color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.slateField,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.slateBorder),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ledAmber,
                  foregroundColor: Colors.black,
                ),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Online payments are checked by your cashier: the app can\'t confirm the money arrived, so always check your e-wallet before marking an order as paid.',
              style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: child,
    );
  }
}
