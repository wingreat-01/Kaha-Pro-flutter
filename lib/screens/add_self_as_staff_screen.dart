import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

/// Shown exactly once per store: right after a brand-new owner
/// finishes signUp() on StoreSetupScreen, staff_users has zero rows
/// for this store, so the normal PIN LoginScreen has nothing to
/// check a PIN against. This screen collects Name + PIN and calls
/// add_staff_user() to seed the owner's own staff record with role
/// 'admin', then hands control back to main.dart via onDone so it
/// can re-check staff_users and fall through to the PIN pad.
///
/// add_staff_user()'s real signature (confirmed via PostgREST's
/// error hint after a param-name mismatch) is
/// add_staff_user(pin, staff_name, staff_role) — the RPC call below
/// matches that.
class AddSelfAsStaffScreen extends StatefulWidget {
  final VoidCallback onDone;
  const AddSelfAsStaffScreen({super.key, required this.onDone});

  @override
  State<AddSelfAsStaffScreen> createState() => _AddSelfAsStaffScreenState();
}

class _AddSelfAsStaffScreenState extends State<AddSelfAsStaffScreen> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    final confirmPin = _confirmPinCtrl.text.trim();

    if (name.isEmpty || pin.isEmpty) {
      setState(() {
        _error = 'Enter your name and a PIN.';
        _loading = false;
      });
      return;
    }
    if (pin.length < 4) {
      setState(() {
        _error = 'PIN needs to be at least 4 digits.';
        _loading = false;
      });
      return;
    }
    if (pin != confirmPin) {
      setState(() {
        _error = "PINs don't match.";
        _loading = false;
      });
      return;
    }

    try {
      await Supabase.instance.client.rpc(
        'add_staff_user',
        params: {
          'staff_name': name,
          'pin': pin,
          'staff_role': 'admin',
        },
      );
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      debugPrint('add_staff_user failed: $e');
      setState(() {
        _error = 'Something went wrong saving your staff account. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
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
                    child: const Icon(Icons.badge_outlined, color: AppColors.ledAmber, size: 26),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ADD YOURSELF AS STAFF',
                    style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "You're set up as the store owner. Now create a\nPIN so you can clock in at the register.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 24),
                  _StaffField(label: 'Your Name', controller: _nameCtrl, hint: 'e.g. Maria'),
                  const SizedBox(height: 14),
                  _StaffField(
                    label: 'PIN',
                    controller: _pinCtrl,
                    hint: '••••',
                    obscure: true,
                    numeric: true,
                  ),
                  const SizedBox(height: 14),
                  _StaffField(
                    label: 'Confirm PIN',
                    controller: _confirmPinCtrl,
                    hint: '••••',
                    obscure: true,
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
                          : const Text('Save & continue'),
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

class _StaffField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool numeric;
  final VoidCallback? onSubmit;

  const _StaffField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
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
          decoration: InputDecoration(hintText: hint),
          onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
        ),
      ],
    );
  }
}
