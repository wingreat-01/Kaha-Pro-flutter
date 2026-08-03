import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../state/transaction_provider.dart';
import '../theme/app_theme.dart';
import 'transaction_detail_modal.dart';

/// Content shown for the "Transactions" tab: every completed sale,
/// newest first, logged automatically by TransactionProvider when
/// checkout is confirmed. Tapping a row opens the full line-item detail.
class TransactionsPanel extends StatelessWidget {
  const TransactionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final summaries = context.watch<TransactionProvider>().dailySummaries;

    if (summaries.isEmpty) {
      return Center(
        child: Text(
          'No transactions yet',
          style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final day = summaries[index];
        final isLast = index == summaries.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DaySummaryHeader(summary: day),
              const SizedBox(height: 10),
              for (final txn in day.transactions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TransactionRow(
                    transaction: txn,
                    onTap: () => showDialog(
                      context: context,
                      barrierColor: Colors.black54,
                      builder: (_) => TransactionDetailModal(transaction: txn),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DaySummaryHeader extends StatelessWidget {
  final DaySummary summary;

  const _DaySummaryHeader({required this.summary});

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _label(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return '${_months[day.month - 1]} ${day.day}, ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                _label(summary.day),
                style: AppTextStyles.mono(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
            ),
            Text(
              '${summary.saleCount} sale${summary.saleCount == 1 ? '' : 's'} · ${summary.itemsSold} item${summary.itemsSold == 1 ? '' : 's'}  ',
              style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
            ),
            Text(
              '₱${summary.totalRevenue.toStringAsFixed(2)}',
              style: AppTextStyles.mono(size: 14, weight: FontWeight.w700, color: AppColors.ledAmber),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: AppColors.slateBorder),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onTap;

  const _TransactionRow({required this.transaction, required this.onTap});

  String _formatTime(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.slate,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.slateBorder, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.slateField,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                transaction.transactionNumber,
                style: AppTextStyles.mono(size: 12, weight: FontWeight.w700, color: AppColors.ledAmber),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${transaction.itemCount} item${transaction.itemCount == 1 ? '' : 's'}',
                    style: AppTextStyles.body(size: 13, weight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(transaction.timestamp),
                    style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '₱${transaction.total.toStringAsFixed(2)}',
              style: AppTextStyles.mono(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
