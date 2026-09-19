import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/currency.dart';
import '../state/currency_provider.dart';
import '../theme/app_theme.dart';

/// Drop-in Settings row: shows the current currency and opens a picker.
/// Usage in the Settings screen:  `const CurrencyPickerTile()`
class CurrencyPickerTile extends StatelessWidget {
  const CurrencyPickerTile({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<CurrencyProvider>().currency;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.payments_outlined, color: AppColors.ledAmber),
      title: Text(
        'Currency',
        style: AppTextStyles.body(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary),
      ),
      subtitle: Text(
        '${current.name} (${current.symbol})',
        style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
      ),
      trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: () => showCurrencyPicker(context),
    );
  }
}

Future<void> showCurrencyPicker(BuildContext context) {
  final provider = context.read<CurrencyProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.75;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.slate,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.slateBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'CURRENCY',
                    style: AppTextStyles.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Changes the symbol and formatting only. Existing prices and past sales are not converted.',
                    style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                  ),
                ),
                Divider(color: AppColors.slateBorder, height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: Currencies.all.length,
                    itemBuilder: (context, index) {
                      final c = Currencies.all[index];
                      final selected = c.code == provider.currency.code;
                      return ListTile(
                        onTap: () async {
                          await provider.setCurrency(c);
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        },
                        leading: SizedBox(
                          width: 44,
                          child: Text(
                            c.symbol,
                            style: AppTextStyles.mono(
                              size: 16,
                              weight: FontWeight.w700,
                              color: selected ? AppColors.ledAmber : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: AppTextStyles.body(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        subtitle: Text(
                          c.code,
                          style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                        ),
                        trailing: selected ? Icon(Icons.check, color: AppColors.tillGreen, size: 20) : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
