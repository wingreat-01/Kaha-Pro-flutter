import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../state/transaction_provider.dart';
import '../theme/app_theme.dart';
import 'transaction_detail_modal.dart';

/// Content shown for the "Transactions" tab: every completed sale,
/// newest first, logged automatically by TransactionProvider when
/// checkout is confirmed. Tapping a row opens the full line-item detail.
/// A calendar button lets the user jump straight to a specific day
/// instead of scrolling through history.
///
/// A PENDING row (an offline-queued sale not yet synced to Supabase)
/// gets an extra discard action so a permanently-failing entry (e.g.
/// its product was deleted before it could sync) doesn't have to sit
/// there retrying forever with no way out.
class TransactionsPanel extends StatefulWidget {
  const TransactionsPanel({super.key});

  @override
  State<TransactionsPanel> createState() => _TransactionsPanelState();
}

class _TransactionsPanelState extends State<TransactionsPanel> {
  // null = no filter, show every day's summary + transactions.
  DateTime? _filterDate;

  Future<void> _pickDate(List<DaySummary> allSummaries) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Earliest day with any recorded sales, so the picker doesn't offer
    // an empty range before the shop had any transactions logged.
    final firstDate = allSummaries.isEmpty
        ? today
        : allSummaries.map((s) => s.day).reduce((a, b) => a.isBefore(b) ? a : b);

    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? today,
      firstDate: firstDate,
      lastDate: today,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.ledAmber,
              onPrimary: AppColors.charcoal,
              surface: AppColors.slate,
              onSurface: AppColors.textPrimary,
            ),
            dialogBackgroundColor: AppColors.slate,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _filterDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _clearFilter() => setState(() => _filterDate = null);

  Future<void> _confirmDiscard(BuildContext context, Transaction txn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text(
          'Discard pending sale?',
          style: AppTextStyles.body(size: 16, weight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: Text(
          'This sale (₱${txn.total.toStringAsFixed(2)}) never synced and will stop retrying. '
          'This can\'t be undone.',
          style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Discard', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledgerRed)),
          ),
        ],
      ),
    );

    if (confirmed == true && txn.localId != null) {
      await context.read<TransactionProvider>().discardPending(txn.localId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSummaries = context.watch<TransactionProvider>().dailySummaries;
    final filterDate = _filterDate;
    final summaries =
        filterDate == null ? allSummaries : allSummaries.where((s) => s.day == filterDate).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 900 : double.infinity),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      if (filterDate != null)
                        Expanded(
                          child: _DateFilterChip(date: filterDate, onClear: _clearFilter),
                        )
                      else
                        const Spacer(),
                      IconButton(
                        onPressed: () => _pickDate(allSummaries),
                        icon: const Icon(Icons.calendar_today_outlined, color: AppColors.textSecondary, size: 18),
                        tooltip: 'Jump to date',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: summaries.isEmpty
                      ? Center(
                          child: Text(
                            filterDate == null ? 'No transactions yet' : 'No transactions on this date',
                            style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
                          ),
                        )
                      : ListView.builder(
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
                                        onDiscard: txn.isPending ? () => _confirmDiscard(context, txn) : null,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Shared label formatting so the day headers and the filter chip always
/// describe the same date the same way ("Today" / "Yesterday" / full date).
String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  return '${_monthNames[day.month - 1]} ${day.day}, ${day.year}';
}

class _DateFilterChip extends StatelessWidget {
  final DateTime date;
  final VoidCallback onClear;

  const _DateFilterChip({required this.date, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.slateField,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ledAmber.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event, color: AppColors.ledAmber, size: 14),
          const SizedBox(width: 6),
          Text(
            _dayLabel(date),
            style: AppTextStyles.mono(size: 12, weight: FontWeight.w700, color: AppColors.ledAmber),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, color: AppColors.textMuted, size: 15),
          ),
        ],
      ),
    );
  }
}

class _DaySummaryHeader extends StatelessWidget {
  final DaySummary summary;

  const _DaySummaryHeader({required this.summary});

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
                _dayLabel(summary.day),
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
  /// Non-null only for a PENDING (offline-queued, unsynced) row —
  /// shows a discard icon in place of the chevron for that row only.
  final VoidCallback? onDiscard;

  const _TransactionRow({required this.transaction, required this.onTap, this.onDiscard});

  String _formatTime(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isPending = transaction.isPending;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.slate,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isPending ? AppColors.ledAmber.withOpacity(0.4) : AppColors.slateBorder,
            width: 1,
          ),
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
            if (onDiscard != null)
              IconButton(
                onPressed: onDiscard,
                icon: const Icon(Icons.delete_outline, color: AppColors.ledgerRed, size: 18),
                tooltip: 'Discard pending sale',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
