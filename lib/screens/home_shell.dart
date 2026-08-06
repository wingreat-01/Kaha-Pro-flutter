import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/user.dart';
import '../widgets/checkout_warmup.dart';
import '../widgets/transactions_panel.dart';
import 'register_screen.dart';
import 'settings_panel.dart';

enum _Section { register, transactions, settings }

/// App shell — owns top-level navigation between the Register (product
/// grid + cart), Transactions history, and Settings (Users, Categories,
/// Products, Store details).
///
/// Register/Transactions/Users/Settings used to be crammed together into
/// the category tab row alongside actual product categories — that both
/// overflowed the tab bar on phone widths and mixed "what am I selling"
/// with "where do I manage the app" in one row. Register, Transactions,
/// and Settings are all header-level icons now (Register first, then
/// Transactions, then Settings, then Logout) so there's always a way
/// back to the product grid from anywhere.
///
/// Now that login is real (Phase 5), Settings is admin-only — a cashier
/// account never sees the gear icon at all, rather than seeing it and
/// being blocked after tapping it.
class HomeShell extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.user, required this.onLogout});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Section _section = _Section.register;

  bool get _isAdmin => widget.user.role == UserRole.admin;

  Widget _body() {
    switch (_section) {
      case _Section.register:
        return RegisterScreen(cashierName: widget.user.name);
      case _Section.transactions:
        return const TransactionsPanel();
      case _Section.settings:
        // Defensive fallback — the gear icon that sets this is hidden
        // entirely for non-admins, so this only matters if _section
        // somehow ends up here some other way.
        return _isAdmin ? const SettingsPanel() : RegisterScreen(cashierName: widget.user.name);
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
          Center(
            child: Text(
              '${widget.user.name} · ${widget.user.role.label}',
              style: AppTextStyles.mono(size: 11, color: AppColors.textMuted, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          _headerIcon(
            icon: Icons.point_of_sale_outlined,
            tooltip: 'Register',
            isActive: _section == _Section.register,
            onTap: () => setState(() => _section = _Section.register),
          ),
          _headerIcon(
            icon: Icons.receipt_long_outlined,
            tooltip: 'Transactions',
            isActive: _section == _Section.transactions,
            onTap: () => setState(() => _section = _Section.transactions),
          ),
          if (_isAdmin)
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
      body: Stack(
        children: [
          _body(),
          const CheckoutWarmup(),
        ],
      ),
    );
  }
}
