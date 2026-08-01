import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final void Function(String username, String password) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    // TODO: wire up to your real auth check (Firebase Auth, API, etc.)
    await Future.delayed(const Duration(milliseconds: 300));
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      setState(() {
        _error = 'Invalid username or password.';
        _loading = false;
      });
      return;
    }
    setState(() => _loading = false);
    widget.onLogin(_userCtrl.text.trim(), _passCtrl.text.trim());
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
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
                  _LabeledField(label: 'Username', controller: _userCtrl, obscure: false),
                  const SizedBox(height: 14),
                  _LabeledField(label: 'Password', controller: _passCtrl, obscure: true, onSubmit: _submit),
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
  final VoidCallback? onSubmit;
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.obscure,
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
          style: AppTextStyles.body(size: 14),
          decoration: InputDecoration(hintText: obscure ? '••••••••' : 'Enter username'),
          onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
        ),
      ],
    );
  }
}
