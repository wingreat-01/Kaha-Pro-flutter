import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'inventory_panel.dart';

/// Settings screen — reached via the gear icon in the header. Houses
/// app-level configuration and admin sections. Users management lives
/// here now (previously its own top-level tab in the register category
/// row) since it's an admin concern, not something a cashier needs
/// mid-sale.
///
/// "Products" opens the real Inventory panel now. The rest are still
/// placeholders for Phase 4 (user list/roles, category editor, store
/// details, about) — the navigation shape is in place ahead of that work.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SettingsSectionLabel('ADMIN'),
        const _SettingsRow(
          icon: Icons.people_outline,
          label: 'Users',
          subtitle: 'Manage cashier & admin accounts',
        ),
        const _SettingsRow(
          icon: Icons.category_outlined,
          label: 'Categories',
          subtitle: 'Edit product categories',
        ),
        _SettingsRow(
          icon: Icons.inventory_2_outlined,
          label: 'Products',
          subtitle: 'Manage the full catalog & stock levels',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InventoryPanel()),
          ),
        ),
        const SizedBox(height: 24),
        const _SettingsSectionLabel('APP'),
        const _SettingsRow(
          icon: Icons.storefront_outlined,
          label: 'Store details',
          subtitle: 'Name, address, receipt footer',
        ),
        const _SettingsRow(
          icon: Icons.info_outline,
          label: 'About',
          subtitle: 'Version, support',
        ),
      ],
    );
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

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
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
        // Rows without a real destination yet (Phase 4) just no-op.
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
                    Text(subtitle, style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
