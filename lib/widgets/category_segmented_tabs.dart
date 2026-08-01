import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Full-width segmented tab bar for phone widths. Scrolls horizontally
/// if there are more categories than fit, but each tab is styled as
/// part of one continuous bar with an underline indicator rather than
/// separate floating chips.
class CategorySegmentedTabs extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  const CategorySegmentedTabs({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.slateBorder, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final category in categories)
              _SegmentedTab(
                label: category,
                isSelected: category == selected,
                onTap: () => onSelected(category),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentedTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.ledAmber : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.body(
            size: 13.5,
            weight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.ledAmber : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
