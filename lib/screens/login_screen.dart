import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import '../state/product_provider.dart';
import '../state/transaction_provider.dart';
import '../theme/app_theme.dart';

/// Staff PIN login (Phase C: shared owner session + PIN-gated
/// staff_users table). Checked via the verify_staff_login() RPC
/// instead of the old in-memory UserProvider list.
///
/// Assumes a store-owner Supabase Auth session is already active —
/// that gets established during first-run owner signup/sign-in
/// (StoreSetupScreen), and the empty-staff_users case is handled by
/// AddSelfAsStaffScreen before this screen is ever reached. Without
/// an active session, current_store_id() resolves to nothing
/// server-side and every PIN would silently fail, so that case gets
/// its own message below rather than surfacing as a confusing
/// "Invalid name or PIN."
class LoginScreen extends StatefulWidget {
  final void Function(AppUser user) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  UserRole _parseRole(String? raw) {
    // verify_staff_login returns role as plain text ('admin' /
    // 'cashier'); UserRole.values.byName throws on anything else,
    // which we don't want mid-login, so fall back to the least
    // privileged role rather than crashing on an unexpected value.
    return UserRole.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => UserRole.cashier,
    );
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (name.isEmpty || pin.isEmpty) {
      setState(() {
        _error = 'Enter your name and PIN.';
        _loading = false;
      });
      return;
    }

    if (Supabase.instance.client.auth.currentSession == null) {
      setState(() {
        _error = 'No store session found. Sign in as the store owner first.';
        _loading = false;
      });
      return;
    }

    try {
      final rows = await Supabase.instance.client.rpc(
        'verify_staff_login',
        params: {'staff_name': name, 'pin': pin},
      ) as List;

      if (rows.isEmpty) {
        // Covers wrong name, wrong PIN, and a locked-out account —
        // verify_staff_login deliberately doesn't distinguish these
        // (see the schema comments), so neither does this message.
        setState(() {
          _error = 'Invalid name or PIN.';
          _loading = false;
        });
        return;
      }

      final row = rows.first as Map<String, dynamic>;
      final matched = AppUser(
        id: row['id'] as String,
        name: row['name'] as String,
        role: _parseRole(row['role'] as String?),
      );

      // Fetch-once-on-login (Phase D + Phase F) — load this store's
      // catalog and transaction history before HomeShell shows. Run in
      // parallel since neither depends on the other's result.
      await Future.wait([
        context.read<ProductProvider>().loadFromSupabase(),
        context.read<TransactionProvider>().loadFromSupabase(),
      ]);

      // Now that both are loaded, retry anything queued while offline.
      // Wired here (rather than inside TransactionProvider itself) so
      // stock deduction for a newly-synced sale can be triggered via
      // ProductProvider without the two providers needing to reference
      // each other directly. Fire-and-forget — login shouldn't block
      // on however long a queue of offline sales takes to replay.
      final productProvider = context.read<ProductProvider>();
      unawaited(
        context.read<TransactionProvider>().syncPending(
              deductStock: (items) => productProvider.deductStockForLineItems(items),
            ),
      );

      if (!mounted) return;
      setState(() => _loading = false);
      widget.onLogin(matched);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong signing in. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              decoration: BoxDecoration(
                color: AppColors.slate,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.slateBorder, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.slateField,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.slateBorder, width: 1),
                    ),
                    child: const Icon(Icons.point_of_sale, color: AppColors.ledAmber, size: 26),
                  ),
                  const SizedBox(height: 12),
                  RichText(
                    text: TextSpan(
                      style: AppTextStyles.mono(size: 18, weight: FontWeight.w700, letterSpacing: 1.2),
                      children: [
                        const TextSpan(text: 'KAHA'),
                        TextSpan(text: 'PRO', style: AppTextStyles.mono(size: 18, weight: FontWeight.w700, color: AppColors.ledAmber, letterSpacing: 1.2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'POINT OF SALE',
                    style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 2),
                  ),
                  const SizedBox(height: 28),
                  _LabeledField(
                    label: 'Name',
                    controller: _nameCtrl,
                    obscure: false,
                    hint: 'Enter your name',
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'PIN',
                    controller: _pinCtrl,
                    obscure: true,
                    hint: '••••',
                    numeric: true,
                    onSubmit: _submit,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3A2600)),
                            )
                          : const Text('Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final String? hint;
  final bool numeric;
  final VoidCallback? onSubmit;
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.obscure,
    this.hint,
    this.numeric = false,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]
              : null,
          style: AppTextStyles.body(size: 14),
          decoration: InputDecoration(hintText: hint ?? (obscure ? '••••••••' : 'Enter username')),
          onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
        ),
      ],
    );
  }
}
