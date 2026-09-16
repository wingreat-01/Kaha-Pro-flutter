import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bounded_content.dart';

/// Light / Dark / System picker, reached from Settings > Theme.
/// Same card-row visual language as SettingsPanel's own rows.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ThemeOptionTile(
              icon: Icons.dark_mode_outlined,
              label: 'Dark',
              subtitle: 'Original charcoal & amber look',
              selected: themeProvider.mode == ThemeMode.dark,
              onTap: () => themeProvider.setMode(ThemeMode.dark),
            ),
            _ThemeOptionTile(
              icon: Icons.light_mode_outlined,
              label: 'Light',
              subtitle: 'Bright surfaces, same amber accent',
              selected: themeProvider.mode == ThemeMode.light,
              onTap: () => themeProvider.setMode(ThemeMode.light),
            ),
            _ThemeOptionTile(
              icon: Icons.brightness_auto_outlined,
              label: 'System',
              subtitle: "Match this device's setting",
              selected: themeProvider.mode == ThemeMode.system,
              onTap: () => themeProvider.setMode(ThemeMode.system),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.ledAmber : AppColors.slateBorder,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
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
              if (selected) const Icon(Icons.check_circle, size: 20, color: AppColors.ledAmber),
            ],
          ),
        ),
      ),
    );
  }
}
