import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Icon per category for the sidebar nav. Falls back to a generic
/// tag icon for anything not listed here (e.g. future real categories).
const Map<String, IconData> _categoryIcons = {
  'All': Icons.grid_view_rounded,
  'Drinks': Icons.local_drink_outlined,
  'Snacks': Icons.cookie_outlined,
  'Rice Meals': Icons.rice_bowl_outlined,
  'Add-ons': Icons.add_circle_outline,
};

/// Persistent left-nav category list for wide/web layouts —
/// dashboard feel instead of a scrolling chip row.
class CategorySidebar extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  const CategorySidebar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: AppColors.slate,
        border: Border(right: BorderSide(color: AppColors.slateBorder, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Text(
              'CATEGORIES',
              style: AppTextStyles.mono(
                size: 11,
                weight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
          ),
          for (final category in categories)
            _SidebarItem(
              label: category,
              icon: _categoryIcons[category] ?? Icons.local_offer_outlined,
              isSelected: category == selected,
              onTap: () => onSelected(category),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.ledAmber.withOpacity(0.12) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? AppColors.ledAmber : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.ledAmber : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.body(
                size: 13.5,
                weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
