import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../theme/app_theme.dart';
import 'led_total.dart';

/// Detail view for one logged transaction — opened by tapping a row in
/// TransactionsPanel. Read-only: shows every line item plus total,
/// cash tendered, and change from that sale.
class TransactionDetailModal extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailModal({super.key, required this.transaction});

  String _formatTimestamp(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final minute = t.minute.toString().padLeft(2, '0');
    return '${t.month}/${t.day}/${t.year} · $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.slate,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slateBorder, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.transactionNumber,
                            style: AppTextStyles.mono(size: 16, weight: FontWeight.w700, color: AppColors.ledAmber),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTimestamp(transaction.timestamp),
                            style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                      splashRadius: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppColors.slateBorder, height: 1),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: transaction.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = transaction.items[index];
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.name} ×${item.quantity}',
                              style: AppTextStyles.body(size: 13.5, color: AppColors.textPrimary),
                            ),
                          ),
                          Text(
                            '₱${item.lineTotal.toStringAsFixed(2)}',
                            style: AppTextStyles.mono(size: 13.5, weight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                LedTotal(amount: transaction.total, label: 'TOTAL'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LedTotal(
                        amount: transaction.cashTendered,
                        label: 'TENDERED',
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LedTotal(
                        amount: transaction.change,
                        label: 'CHANGE',
                        fontSize: 18,
                        color: AppColors.tillGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
