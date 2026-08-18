import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/user.dart';
import '../widgets/checkout_warmup.dart';
import '../widgets/transactions_panel.dart';
import 'register_screen.dart';
import 'reports_screen.dart';
import 'settings_panel.dart';
import 'ai_assistant_screen.dart';
import '../state/transaction_provider.dart';
import '../state/product_provider.dart';
import '../state/ingredient_provider.dart';
import '../state/recipe_provider.dart';
import '../state/store_provider.dart';

enum _Section { register, transactions, reports, assistant, settings }

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
///
/// Also owns the offline-queue "faster than next login" retry: this
/// widget stays mounted for the whole logged-in session, so it's the
/// right place for a connectivity listener that needs to outlive any
/// single screen. login_screen.dart's existing syncPending() call still
/// covers "was offline the whole time the app was closed" — this adds
/// the mid-shift case (connectivity returns while the app is open) on
/// top of that, without changing what counts as a successful sync.
///
/// TransactionProvider/ProductProvider live in lib/state/.
class HomeShell extends StatefulWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.user, required this.onLogout});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Section _section = _Section.register;

  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _syncingFromConnectivity = false;

  bool get _isAdmin => widget.user.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  /// Fires on any connectivity change (any transport, not specifically
  /// wifi). If there's now a connection and something is queued,
  /// retries immediately instead of waiting for the next sign-in.
  /// syncPending() is a no-op if the queue is empty, and a genuine
  /// PostgrestException/AuthException-type rejection still leaves an
  /// entry queued (see transaction_provider.dart) — this listener only
  /// changes when the retry is attempted, not what counts as success.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (!mounted || _syncingFromConnectivity) return;

    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    if (!hasConnection) return;

    final transactionProvider = context.read<TransactionProvider>();
    if (transactionProvider.pendingCount == 0) return;

    final productProvider = context.read<ProductProvider>();
    final recipeProvider = context.read<RecipeProvider>();
    final ingredientProvider = context.read<IngredientProvider>();
    _syncingFromConnectivity = true;
    transactionProvider
        .syncPending(deductStock: (items) async {
          await productProvider.deductStockForLineItems(items);
          try {
            await recipeProvider.deductForLineItems(items, ingredientProvider);
          } catch (_) {
            // Swallowed deliberately, same reasoning as login_screen.dart's
            // sync call — negative-stock policy is allow/no-warning, and a
            // failure here shouldn't block the rest of the offline queue.
          }
        })
        .whenComplete(() => _syncingFromConnectivity = false);
  }

  Widget _body() {
    switch (_section) {
      case _Section.register:
        return RegisterScreen(cashierName: widget.user.name);
      case _Section.transactions:
        return const TransactionsPanel();
      case _Section.reports:
        // Defensive fallback — same reasoning as settings below: the
        // header icon that sets this is hidden entirely for
        // non-admins, so this only matters if _section somehow ends
        // up here some other way.
        return _isAdmin
            ? ReportsScreen(
                reportBuilder: (range) => context.read<TransactionProvider>().reportFor(range),
              )
            : RegisterScreen(cashierName: widget.user.name);
      case _Section.assistant:
        // Defensive fallback — same reasoning as reports/settings: the
        // header icon that sets this is hidden entirely for
        // non-admins, so this only matters if _section somehow ends
        // up here some other way.
        return _isAdmin ? const AiAssistantScreen() : RegisterScreen(cashierName: widget.user.name);
      case _Section.settings:
        // Defensive fallback — the gear icon that sets this is hidden
        // entirely for non-admins, so this only matters if _section
        // somehow ends up here some other way.
        return _isAdmin
            ? SettingsPanel(staffId: widget.user.id, staffName: widget.user.name)
            : RegisterScreen(cashierName: widget.user.name);
    }
  }

  Widget _headerIcon({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    int badgeCount = 0,
    // Plain dot, no number — for a state that needs attention but
    // isn't a count of anything (e.g. "your trial is ending soon").
    // A numeric badge would misleadingly imply "3 things pending"
    // when there's really just one ongoing condition to notice.
    bool showWarningDot = false,
  }) {
    final button = IconButton(
      icon: Icon(icon, color: isActive ? AppColors.ledAmber : AppColors.textSecondary),
      tooltip: tooltip,
      onPressed: onTap,
    );
    if (badgeCount <= 0 && !showWarningDot) return button;

    // A queued-but-unsynced sale count on the Transactions icon — the
    // only other sign of a pending sale is its #PENDING row inside the
    // tab itself, which isn't visible until the cashier is already on
    // that screen. This surfaces it from anywhere in the app.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: 4,
          top: 4,
          child: IgnorePointer(
            child: showWarningDot
                ? Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.ledgerRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.slate, width: 1.5),
                    ),
                  )
                : Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: BoxDecoration(
                color: AppColors.ledgerRed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.slate, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeCount > 9 ? '9+' : '$badgeCount',
                style: AppTextStyles.mono(size: 9, weight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = context.watch<TransactionProvider>().pendingCount;

    // Trial/plan urgency — shown as a plain dot on the Settings icon
    // rather than the full "Free trial · N days left" text anywhere
    // outside Settings itself, so it stays quiet most of the time and
    // only draws the eye once it actually matters (last few days, or
    // already expired). Full detail always lives in Settings -> Plan.
    final store = context.watch<StoreProvider>().store;
    final daysLeft = store?.trialDaysRemaining;
    final planNeedsAttention = store != null && (store.isExpired || (daysLeft != null && daysLeft <= 3));
    final settingsTooltip = store == null
        ? 'Settings'
        : store.isExpired
            ? 'Settings — trial expired'
            : planNeedsAttention
                ? 'Settings — trial ends in $daysLeft day${daysLeft == 1 ? '' : 's'}'
                : 'Settings';

    // Assistant tab gets its own quiet dot when it's actually unusable
    // (expired trial, or this cycle's credits are gone) rather than
    // reusing the Settings dot — the two can be true independently
    // (e.g. plenty of trial days left but credits used up early).
    final assistantBlocked = store != null && !store.canUseAiAssistant;
    final assistantTooltip = store == null
        ? 'AI Assistant'
        : store.isExpired
            ? 'AI Assistant — trial expired'
            : assistantBlocked
                ? 'AI Assistant — out of credits this month'
                : 'AI Assistant';

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
            tooltip: pendingCount > 0
                ? 'Transactions ($pendingCount pending)'
                : 'Transactions',
            isActive: _section == _Section.transactions,
            onTap: () => setState(() => _section = _Section.transactions),
            badgeCount: pendingCount,
          ),
          if (_isAdmin)
            _headerIcon(
              icon: Icons.bar_chart_outlined,
              tooltip: 'Reports',
              isActive: _section == _Section.reports,
              onTap: () => setState(() => _section = _Section.reports),
            ),
          if (_isAdmin)
            _headerIcon(
              icon: Icons.auto_awesome_outlined,
              tooltip: assistantTooltip,
              isActive: _section == _Section.assistant,
              onTap: () => setState(() => _section = _Section.assistant),
              showWarningDot: assistantBlocked,
            ),
          if (_isAdmin)
            _headerIcon(
              icon: Icons.settings_outlined,
              tooltip: settingsTooltip,
              isActive: _section == _Section.settings,
              onTap: () => setState(() => _section = _Section.settings),
              showWarningDot: planNeedsAttention,
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
