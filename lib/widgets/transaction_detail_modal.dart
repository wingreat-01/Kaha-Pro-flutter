import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import '../state/currency_provider.dart';
import '../theme/app_theme.dart';
import 'led_total.dart';
import 'void_sale_dialog.dart';

/// Detail view for one logged transaction — opened by tapping a row in
/// TransactionsPanel. Shows every line item plus total, cash tendered,
/// and change from that sale, and the Void sale action (admin-approved
/// — see void_sale_dialog.dart) or the void record if already voided.
class TransactionDetailModal extends StatelessWidget {
  final Transaction transaction;
  // Who's logged in — decides "Void sale" (admin) vs "Request void"
  // (cashier, needs an admin's PIN). Null hides the action entirely.
  final AppUser? currentUser;

  const TransactionDetailModal({super.key, required this.transaction, this.currentUser});

  Future<void> _void(BuildContext context) async {
    final voided = await showVoidSaleDialog(
      context,
      transaction: transaction,
      currentUser: currentUser!,
    );
    if (voided == true && context.mounted) Navigator.of(context).pop();
  }

  Widget _voidedBanner() {
    final at = transaction.voidedAt!;
    final by = transaction.voidedByName;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.ledgerRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ledgerRed.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VOIDED',
            style: AppTextStyles.mono(size: 11, weight: FontWeight.w700, color: AppColors.ledgerRed, letterSpacing: 1),
          ),
          const SizedBox(height: 3),
          Text(
            '${by == null ? '' : 'By $by · '}${_formatTimestamp(at)}',
            style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
          ),
          if (transaction.voidReason != null) ...[
            const SizedBox(height: 2),
            Text(
              transaction.voidReason!,
              style: AppTextStyles.body(size: 12.5, color: AppColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }

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
                      icon: Icon(Icons.close, color: AppColors.textMuted, size: 20),
                      splashRadius: 18,
                    ),
                  ],
                ),
                if (transaction.isVoided) ...[
                  const SizedBox(height: 10),
                  _voidedBanner(),
                ],
                const SizedBox(height: 12),
                Divider(color: AppColors.slateBorder, height: 1),
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
                            context.money(item.lineTotal),
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
                // Pending (unsynced) sales are discarded from the list
                // instead — there's no server row to void yet.
                if (currentUser != null && !transaction.isVoided && !transaction.isPending) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => _void(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ledgerRed,
                      side: BorderSide(color: AppColors.ledgerRed.withValues(alpha: 0.6)),
                    ),
                    icon: Icon(
                      currentUser!.role == UserRole.admin ? Icons.block : Icons.admin_panel_settings_outlined,
                      size: 18,
                    ),
                    label: Text(
                      currentUser!.role == UserRole.admin ? 'Void sale' : 'Request void (admin approval)',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
