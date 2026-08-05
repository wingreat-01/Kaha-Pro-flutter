import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../state/user_provider.dart';
import '../theme/app_theme.dart';

/// Real auth, wired to UserProvider (Phase 5). Matches on name
/// (case-insensitive — typing "admin" matches an account named "Admin")
/// and an exact PIN. There's still no hashing/session/token layer here —
/// that's the Supabase Auth track — this just replaces the old
/// accept-any-non-empty-string placeholder with a real check against
/// the accounts created in Settings → Users.
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

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    await Future.delayed(const Duration(milliseconds: 300));

    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (name.isEmpty || pin.isEmpty) {
      setState(() {
        _error = 'Enter your name and PIN.';
        _loading = false;
      });
      return;
    }

    final users = context.read<UserProvider>().users;
    AppUser? match;
    for (final u in users) {
      if (u.name.toLowerCase() == name.toLowerCase() && u.pin == pin) {
        match = u;
        break;
      }
    }

    if (match == null) {
      setState(() {
        _error = 'Invalid name or PIN.';
        _loading = false;
      });
      return;
    }

    setState(() => _loading = false);
    widget.onLogin(match);
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
