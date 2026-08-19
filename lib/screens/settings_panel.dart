import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../state/ingredient_provider.dart';
import '../state/store_provider.dart';
import 'ingredients_panel.dart';
import 'inventory_panel.dart';
import 'users_panel.dart';
import 'categories_panel.dart';
import 'payment_methods_panel.dart';
import '../widgets/bounded_content.dart';
import '../models/store.dart';
import 'upgrade_screen.dart';
import 'store_details_panel.dart';

/// Settings screen — reached via the gear icon in the header. Houses
/// app-level configuration and admin sections. Users management lives
/// here now (previously its own top-level tab in the register category
/// row) since it's an admin concern, not something a cashier needs
/// mid-sale.
///
/// "Products" opens the real Inventory panel, "Users" opens the real
/// Users panel, "Categories" opens the real Categories panel. Store
/// details and About are still placeholders (Phase 5).
class SettingsPanel extends StatelessWidget {
  // Logged-in staff member — forwarded to IngredientsPanel so manual
  // stock adjustments can be attributed (see ingredients_panel.dart's
  // _StockAdjustDialog). Same info HomeShell already passes into
  // RegisterScreen as cashierName.
  final String staffId;
  final String staffName;

  const SettingsPanel({super.key, required this.staffId, required this.staffName});

  Future<void> _toggleSeniorPwdDiscount(BuildContext context, bool value) async {
    try {
      await context.read<StoreProvider>().setSeniorPwdDiscountEnabled(value);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save — check your connection and try again.')),
      );
    }
  }

  Future<void> _toggleReceiptPrinting(BuildContext context, bool value) async {
    try {
      await context.read<StoreProvider>().setReceiptPrintingEnabled(value);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save — check your connection and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeProvider = context.watch<StoreProvider>();
    final label = storeProvider.businessTypeLabel;
    final store = storeProvider.store;
    final lowStockCount = context.watch<IngredientProvider>().lowStockIngredients.length;

    return BoundedContent(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
        const _SettingsSectionLabel('ADMIN'),
        _SettingsRow(
          icon: Icons.people_outline,
          label: 'Users',
          subtitle: 'Manage cashier & admin accounts',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UsersPanel()),
          ),
        ),
        _SettingsRow(
          icon: Icons.category_outlined,
          label: 'Categories',
          subtitle: 'Edit product categories',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CategoriesPanel()),
          ),
        ),
        _SettingsRow(
          icon: Icons.payments_outlined,
          label: 'Payment Methods',
          subtitle: 'Set which payment modes you accept',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PaymentMethodsPanel()),
          ),
        ),
        _ToggleSettingsRow(
          icon: Icons.accessible_outlined,
          label: 'Senior / PWD Discount',
          subtitle: storeProvider.seniorPwdDiscountEnabled
              ? 'Enabled — visible at checkout'
              : 'Disabled — hidden from checkout',
          value: storeProvider.seniorPwdDiscountEnabled,
          onChanged: (value) => _toggleSeniorPwdDiscount(context, value),
        ),
        _ToggleSettingsRow(
          icon: Icons.print_outlined,
          label: 'Receipt Printing',
          subtitle: storeProvider.receiptPrintingEnabled
              ? 'Enabled — receipt shown after checkout'
              : 'Disabled — no receipt after checkout',
          value: storeProvider.receiptPrintingEnabled,
          onChanged: (value) => _toggleReceiptPrinting(context, value),
        ),
        _SettingsRow(
          icon: Icons.inventory_2_outlined,
          label: 'Products',
          subtitle: 'Manage the full catalog & stock levels',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InventoryPanel()),
          ),
        ),
        _SettingsRow(
          icon: Icons.inventory_outlined,
          label: label,
          subtitle: lowStockCount > 0
              ? '$lowStockCount running low'
              : 'Raw materials & supplies stock',
          badgeCount: lowStockCount,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => IngredientsPanel(staffId: staffId, staffName: staffName)),
          ),
        ),
        const SizedBox(height: 24),
        const _SettingsSectionLabel('APP'),
        _SettingsRow(
          icon: Icons.workspace_premium_outlined,
          label: 'Plan',
          subtitle: _planSubtitle(store),
          isWarning: store?.isExpired ?? false,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UpgradeScreen()),
          ),
        ),
        _SettingsRow(
          icon: Icons.storefront_outlined,
          label: 'Store details',
          subtitle: 'Name, address, receipt footer',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StoreDetailsPanel()),
          ),
        ),
        const _SettingsRow(
          icon: Icons.info_outline,
          label: 'About',
          subtitle: 'Version, support',
        ),
        ],
      ),
    );
  }
}

/// Subtitle copy for the Plan row. Free-tier stores show a trial
/// countdown (or "expired") since that's the state most likely to
/// change/matter; paid plans just show the plan name, since they
/// don't carry a plan_expires_at date (see Store.isExpired).
String _planSubtitle(Store? store) {
  if (store == null) return '';
  switch (store.plan) {
    case 'basic':
      return 'Basic plan';
    case 'pro':
      return 'Pro plan';
    case 'expired':
      return 'Trial expired · upgrade to continue';
    default: // 'free'
      if (store.isExpired) return 'Trial expired · upgrade to continue';
      final days = store.trialDaysRemaining;
      if (days != null) {
        return 'Free trial · $days day${days == 1 ? '' : 's'} left';
      }
      return 'Free trial';
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String label;
  const _SettingsSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        label,
        style: AppTextStyles.mono(size: 11, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 2),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final int badgeCount;
  // Colors the subtitle red like a badgeCount would, without showing
  // a numeric badge -- for states like "Trial expired" where there's
  // no count to display.
  final bool isWarning;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
    this.badgeCount = 0,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Rows without a real destination yet (rest of Phase 4 / Phase 5) just no-op.
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.slateField,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slateBorder, width: 1),
                ),
                child: Icon(icon, size: 18, color: AppColors.ledAmber),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.body(
                        size: 12,
                        // Same red used for the LOW badge in Inventory/
                        // Ingredients rows — this subtitle is standing
                        // in for that same signal one level up the nav.
                        color: (badgeCount > 0 || isWarning) ? AppColors.ledgerRed : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (badgeCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  constraints: const BoxConstraints(minWidth: 20),
                  decoration: BoxDecoration(
                    color: AppColors.ledgerRed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.mono(size: 10.5, weight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Same card shell as _SettingsRow, but for a row that's a direct
/// on/off setting rather than a navigation link — a trailing Switch
/// instead of a chevron, no onTap/InkWell on the whole row (so an
/// accidental tap on the label doesn't flip the switch).
class _ToggleSettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleSettingsRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.slateField,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.slateBorder, width: 1),
              ),
              child: Icon(icon, size: 18, color: AppColors.ledAmber),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.tillGreen,
            ),
          ],
        ),
      ),
    );
  }
}
