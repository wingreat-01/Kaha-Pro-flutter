import 'package:flutter/material.dart';
import '../models/store.dart';
import '../models/transaction.dart';
import '../theme/app_theme.dart';

/// Post-checkout receipt preview — Stage 1 of the receipt printing
/// feature (see StoreProvider.receiptPrintingEnabled / the Settings
/// toggle). Renders the same info a physical receipt would show,
/// styled as the app's "torn paper ticket" (paper cream #F6F1E4,
/// IBM Plex Mono) per the design system, but the Print button is a
/// stub for now — Stage 2 wires this up to an actual Bluetooth
/// thermal printer once that's built and tested against real
/// hardware. Kept as a full page (not a dialog) since a receipt is
/// the kind of thing a cashier might want to look at for a moment,
/// scroll through a longer cart, or eventually screenshot/share.
class ReceiptPreviewScreen extends StatelessWidget {
  final Transaction transaction;
  final Store? store;

  const ReceiptPreviewScreen({super.key, required this.transaction, this.store});

  void _printStub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Printer connection is coming in a future update.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        title: const Text('Receipt'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: _ReceiptTicket(transaction: transaction, store: store),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _printStub(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.slateBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.print_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Print'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.tillGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptTicket extends StatelessWidget {
  final Transaction transaction;
  final Store? store;

  const _ReceiptTicket({required this.transaction, required this.store});

  @override
  Widget build(BuildContext context) {
    final mono = (double size, {FontWeight weight = FontWeight.w500}) =>
        AppTextStyles.mono(size: size, weight: weight, color: const Color(0xFF2A241C));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.paperCream,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Store header ──
          Text(store?.name ?? 'Store', textAlign: TextAlign.center, style: mono(15, weight: FontWeight.w700)),
          if ((store?.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(store!.address!, textAlign: TextAlign.center, style: mono(10.5)),
          ],
          if ((store?.contactNumber ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(store!.contactNumber!, textAlign: TextAlign.center, style: mono(10.5)),
          ],
          if ((store?.tin ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('TIN: ${store!.tin!}', textAlign: TextAlign.center, style: mono(10.5)),
          ],
          if ((store?.permitNumber ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(store!.permitNumber!, textAlign: TextAlign.center, style: mono(10.5)),
          ],
          const SizedBox(height: 14),
          _DashedDivider(),
          const SizedBox(height: 10),

          // ── Transaction meta ──
          _MetaRow(label: 'Receipt #', value: transaction.transactionNumber, style: mono),
          _MetaRow(label: 'Date', value: _formatDateTime(transaction.timestamp), style: mono),
          if ((transaction.cashierName ?? '').isNotEmpty)
            _MetaRow(label: 'Cashier', value: transaction.cashierName!, style: mono),
          const SizedBox(height: 10),
          _DashedDivider(),
          const SizedBox(height: 10),

          // ── Line items ──
          for (final item in transaction.items) ...[
            Text(item.name, style: mono(12, weight: FontWeight.w600)),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${item.quantity} x ${item.price.toStringAsFixed(2)}', style: mono(11)),
                  Text(item.lineTotal.toStringAsFixed(2), style: mono(12, weight: FontWeight.w600)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          _DashedDivider(),
          const SizedBox(height: 10),

          // ── Totals / discount breakdown ──
          if (transaction.hasDiscount) ...[
            _AmountRow(label: 'Subtotal', value: transaction.total + transaction.discountAmount + transaction.vatExemptAmount, style: mono),
            _AmountRow(label: 'Less VAT', value: -transaction.vatExemptAmount, style: mono),
            _AmountRow(
              label: '20% ${transaction.discountType == 'senior' ? 'Senior' : 'PWD'} Discount',
              value: -transaction.discountAmount,
              style: mono,
            ),
            const SizedBox(height: 4),
          ],
          _AmountRow(label: 'TOTAL', value: transaction.total, style: mono, emphasize: true),
          const SizedBox(height: 6),
          _AmountRow(label: transaction.paymentMethodName ?? 'Payment', value: transaction.cashTendered, style: mono),
          if (transaction.change > 0) _AmountRow(label: 'Change', value: transaction.change, style: mono),

          if (transaction.hasDiscount) ...[
            const SizedBox(height: 10),
            _DashedDivider(),
            const SizedBox(height: 10),
            Text('${transaction.discountType == 'senior' ? 'Senior Citizen' : 'PWD'}: ${transaction.discountHolderName ?? ''}',
                style: mono(10.5)),
            if ((transaction.discountIdNumber ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('ID No: ${transaction.discountIdNumber!}', style: mono(10.5)),
              ),
          ],

          if ((store?.receiptFooter ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            _DashedDivider(),
            const SizedBox(height: 12),
            Text(store!.receiptFooter!, textAlign: TextAlign.center, style: mono(11)),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final h24 = dt.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final ampm = h24 < 12 ? 'AM' : 'PM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '$h12:$mm $ampm';
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle Function(double, {FontWeight weight}) style;

  const _MetaRow({required this.label, required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style(11)),
          Text(value, style: style(11, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double value;
  final TextStyle Function(double, {FontWeight weight}) style;
  final bool emphasize;

  const _AmountRow({required this.label, required this.value, required this.style, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final isNegative = value < 0;
    final text = '${isNegative ? '-' : ''}${value.abs().toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style(emphasize ? 13 : 11.5, weight: emphasize ? FontWeight.w700 : FontWeight.w500)),
          Text(text, style: style(emphasize ? 14 : 11.5, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const dashSpace = 4.0;
        final count = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          children: List.generate(
            count,
            (_) => const SizedBox(
              width: dashWidth,
              height: 1.5,
              child: DecoratedBox(decoration: BoxDecoration(color: Color(0x552A241C))),
            ),
          ).expand((w) => [w, const SizedBox(width: dashSpace)]).toList(),
        );
      },
    );
  }
}
