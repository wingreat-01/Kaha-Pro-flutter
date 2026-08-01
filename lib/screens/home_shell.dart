import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'register_screen.dart';

/// App shell — currently hosts the Register screen (Phase 2).
/// Transactions / Inventory / Admin tabs get added here in Phase 3-4.
class HomeShell extends StatelessWidget {
  final String username;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.username, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        elevation: 0,
        title: Text('KAHAPRO', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
            tooltip: 'Logout',
            onPressed: onLogout,
          ),
        ],
      ),
      body: const RegisterScreen(),
    );
  }
}
