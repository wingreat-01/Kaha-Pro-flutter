import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/transactions_panel.dart';
import 'register_screen.dart';
import 'settings_panel.dart';

enum _Section { register, transactions, settings }

/// App shell — owns top-level navigation between the Register (product
/// grid + cart), Transactions history, and Settings (which now also
/// houses Users management, Phase 4).
///
/// Register/Transactions/Users/Settings used to be crammed together into
/// the category tab row alongside actual product categories — that both
/// overflowed the tab bar on phone widths and mixed "what am I selling"
/// with "where do I manage the app" in one row. Transactions and Settings
/// are header-level concerns now, next to Logout; Register (with its own
/// category tabs) is the default body.
class HomeShell extends StatefulWidget {
  final String username;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.username, required this.onLogout});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Section _section = _Section.register;

  Widget _body() {
    switch (_section) {
      case _Section.register:
        return const RegisterScreen();
      case _Section.transactions:
        return const TransactionsPanel();
      case _Section.settings:
        return const SettingsPanel();
    }
  }

  Widget _headerIcon({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return IconButton(
      icon: Icon(icon, color: isActive ? AppColors.ledAmber : AppColors.textSecondary),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        elevation: 0,
        title: Text('KAHAPRO', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700, letterSpacing: 1)),
        actions: [
          _headerIcon(
            icon: Icons.receipt_long_outlined,
            tooltip: 'Transactions',
            isActive: _section == _Section.transactions,
            onTap: () => setState(() => _section = _Section.transactions),
          ),
          _headerIcon(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            isActive: _section == _Section.settings,
            onTap: () => setState(() => _section = _Section.settings),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
            tooltip: 'Logout',
            onPressed: widget.onLogout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(),
    );
  }
}
