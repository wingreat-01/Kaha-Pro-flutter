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
          data: {'store_name': storeName},
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
                ],
              ),
            ),
          ),
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
