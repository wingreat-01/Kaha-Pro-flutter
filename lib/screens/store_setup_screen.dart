import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

/// First-run screen, shown ahead of LoginScreen whenever there's no
/// active Supabase Auth session on the device.
///
/// Two modes:
///  - Create your store: Store Name + Email + Password -> signUp(),
///    with store_name passed as user metadata. The handle_new_user
///    trigger picks that up server-side and atomically creates the
///    stores row, the store_members row (role owner), and the seeded
///    Uncategorized category.
///  - Sign in: Email + Password -> signInWithPassword(), for an owner
///    who already has an account and is reinstalling / on a new device.
///
/// This screen does NOT navigate on success. main.dart listens to
/// Supabase.instance.client.auth.onAuthStateChange and rebuilds the
/// routing tree itself once a session appears -- that keeps session
/// state in exactly one place instead of duplicating it here.
///
/// Assumes "Confirm email" is turned OFF in Supabase's Auth ->
/// Email provider settings, per the earlier decision -- otherwise
/// signUp() won't return a live session and this screen will just
/// sit there after a successful call with no visible next step.
class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({super.key});

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final _storeNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isSignIn = false;
  bool _loading = false;
  String? _error;
  String? _info;

  // Defaults to 'general' ("Raw Materials") -- matches the
  // backward-compatible default on the stores.business_type column,
  // so an owner who doesn't touch this selector still gets a sane
  // label instead of an unset/null value.
  String _businessType = 'general';

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _info = null;
      _loading = true;
    });

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Enter your email and password.';
        _loading = false;
      });
      return;
    }

    try {
      if (_isSignIn) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        // Success falls through with no navigation call -- the auth
        // state stream in main.dart picks up the new session.
      } else {
        final storeName = _storeNameCtrl.text.trim();
        if (storeName.isEmpty) {
          setState(() {
            _error = 'Enter a store name.';
            _loading = false;
          });
          return;
        }
        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {
            'store_name': storeName,
            'business_type': _businessType,
          },
        );

        if (res.session == null) {
          // "Confirm email" is on in Supabase's Auth settings: the
          // account (and the stores/store_members/category rows via
          // handle_new_user) is created, but no session comes back
          // until they click the link in their inbox. Without this,
          // the screen just sat there looking unresponsive.
          setState(() {
            _loading = false;
            _isSignIn = true;
            _info = 'Account created for $email. Check your inbox for a '
                'confirmation link, then sign in here.';
          });
          return;
        }
        // Confirmation is off -- session came back immediately, and
        // the auth state stream in main.dart takes it from here.
      }
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
      return;
    } catch (e) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
      return;
    }

    if (mounted) setState(() => _loading = false);
  }

  void _toggleMode() {
    setState(() {
      _isSignIn = !_isSignIn;
      _error = null;
      _info = null;
    });
  }

  void _openForgotPasswordDialog() {
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    showDialog(
      context: context,
      builder: (dialogContext) => _ForgotPasswordDialog(initialEmailCtrl: resetEmailCtrl),
    );
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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
                    child: const Icon(Icons.storefront, color: AppColors.ledAmber, size: 26),
                  ),
                  const SizedBox(height: 12),
                  RichText(
                    text: TextSpan(
                      style: AppTextStyles.mono(size: 18, weight: FontWeight.w700, letterSpacing: 1.2),
                      children: [
                        const TextSpan(text: 'KAHA'),
                        TextSpan(
                          text: 'PRO',
                          style: AppTextStyles.mono(size: 18, weight: FontWeight.w700, color: AppColors.ledAmber, letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isSignIn ? 'SIGN IN TO YOUR STORE' : 'SET UP YOUR STORE',
                    style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 2),
                  ),
                  const SizedBox(height: 28),
                  if (!_isSignIn) ...[
                    _SetupField(label: 'Store Name', controller: _storeNameCtrl, hint: 'e.g. Kaha Café'),
                    const SizedBox(height: 14),
                    _BusinessTypePicker(
                      value: _businessType,
                      onChanged: (v) => setState(() => _businessType = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _SetupField(label: 'Email', controller: _emailCtrl, hint: 'you@email.com'),
                  const SizedBox(height: 14),
                  _SetupField(
                    label: 'Password',
                    controller: _passwordCtrl,
                    hint: '••••••••',
                    obscure: true,
                    onSubmit: _submit,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed)),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: AppTextStyles.body(size: 13, color: AppColors.tillGreen)),
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
                          : Text(_isSignIn ? 'Sign in' : 'Create store'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loading ? null : _toggleMode,
                    child: Text(
                      _isSignIn ? "Don't have a store yet? Create one" : 'Already have a store? Sign in',
                      style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
                    ),
                  ),
                  if (_isSignIn) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _loading ? null : _openForgotPasswordDialog,
                      child: Text(
                        'Forgot password?',
                        style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three-way picker for stores.business_type. Values match the DB
/// check constraint exactly (see 003_add_store_business_type.sql):
/// 'food_beverage' | 'retail_hardware' | 'general'.
class _BusinessTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _BusinessTypePicker({required this.value, required this.onChanged});

  static const _options = [
    (value: 'food_beverage', label: 'Café / Food'),
    (value: 'retail_hardware', label: 'Retail / Hardware'),
    (value: 'general', label: 'General'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What kind of business?',
          style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final opt in _options) ...[
              Expanded(child: _Chip(
                label: opt.label,
                selected: value == opt.value,
                onTap: () => onChanged(opt.value),
              )),
              if (opt != _options.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.ledAmber.withOpacity(0.14) : AppColors.slateField,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.ledAmber : AppColors.slateBorder,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(
            size: 12,
            color: selected ? AppColors.ledAmber : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Email-entry dialog that requests a Supabase password-reset link.
/// Deliberately doesn't try to distinguish "no account with that
/// email" from "email sent" in its success message -- doing so would
/// let someone probe which emails have accounts, same reasoning as
/// LoginScreen's merged "Invalid name or PIN" message.
///
/// IMPORTANT: resetPasswordForEmail's redirectTo must point at a deep
/// link this app actually handles, or the reset link in the email
/// will open in a browser with nowhere useful to land. If deep
/// linking isn't set up yet, leave redirectTo unset for now -- the
/// user can still complete the reset via Supabase's default hosted
/// page, they just won't be dropped back into the app automatically.
class _ForgotPasswordDialog extends StatefulWidget {
  final TextEditingController initialEmailCtrl;
  const _ForgotPasswordDialog({required this.initialEmailCtrl});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  bool _loading = false;
  String? _error;
  bool _sent = false;

  Future<void> _send() async {
    final email = widget.initialEmailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        // redirectTo: 'io.supabase.kahapro://reset-callback/',
        // ^ set this once a deep link route exists to catch the
        // callback; until then the hosted Supabase page still works.
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESET PASSWORD',
              style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.5),
            ),
            const SizedBox(height: 16),
            if (_sent) ...[
              Text(
                'If an account exists for that email, a reset link is on its way. Check your inbox.',
                style: AppTextStyles.body(size: 13, color: AppColors.tillGreen),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Done', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber)),
                ),
              ),
            ] else ...[
              Text(
                'Email',
                style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: widget.initialEmailCtrl,
                autofocus: true,
                style: AppTextStyles.body(size: 14),
                decoration: const InputDecoration(hintText: 'you@email.com'),
                onSubmitted: (_) => _send(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _send,
                    child: _loading
                        ? const SizedBox(
                            height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3A2600)),
                          )
                        : const Text('Send reset link'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final VoidCallback? onSubmit;

  const _SetupField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
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
          decoration: InputDecoration(hintText: hint),
          onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
        ),
      ],
    );
  }
}
