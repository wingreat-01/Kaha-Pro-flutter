import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/device_session_service.dart';

// Play Store requires a privacy policy link reachable from within the
// app itself (not just the Play Console listing), and reviewers check
// the account-creation screen specifically since that's where personal
// data -- email/password here -- is first collected. See also
// login_screen.dart, which carries the same link for staff accounts
// that never see this screen.
const _kPrivacyPolicyUrl = 'https://merq.prohubapps.com/privacy.html';

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

  // Set when a sign-in succeeded against Supabase Auth but this
  // device lost the single-active-device claim to a different one --
  // see DeviceSessionService. Non-null while the "already signed in
  // elsewhere" state is showing, so the UI can offer the force-claim
  // recovery action instead of just a plain error.
  String? _blockedByDeviceLabel;

  // Defaults to 'general' ("Raw Materials") -- matches the
  // backward-compatible default on the stores.business_type column,
  // so an owner who doesn't touch this selector still gets a sane
  // label instead of an unset/null value.
  String _businessType = 'general';

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _info = null;
      _blockedByDeviceLabel = null;
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
        // A live Supabase session now exists on this device regardless
        // of what happens next -- _claimThisDevice() below is what
        // decides whether it's allowed to stay that way.
        final claimed = await _claimThisDevice();
        if (!claimed) return;
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
        // Confirmation is off -- session came back immediately. A
        // brand-new account can't already have another device holding
        // a claim, but claiming here still seeds the row so this
        // device is the recorded one from the start.
        final claimed = await _claimThisDevice();
        if (!claimed) return;
        // The auth state stream in main.dart takes it from here.
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

  /// Attempts to claim the single-active-device slot for this login.
  /// Called right after a successful signInWithPassword()/signUp(), so
  /// a real session already exists on this device either way -- if the
  /// claim is refused, this signs that session back out immediately so
  /// "blocked" actually means blocked, not "logged in but nagged."
  ///
  /// Returns true if this device now holds the claim (caller should
  /// fall through as a normal successful login). Returns false if it
  /// was refused (caller should return immediately -- _blockedByDeviceLabel
  /// and _loading are already set here).
  Future<bool> _claimThisDevice({bool force = false}) async {
    final result = await DeviceSessionService.claim(
      deviceLabel: _deviceLabel(),
      force: force,
    );
    if (result.allowed) return true;

    // Refused -- sign this device's brand-new session back out so it
    // can't quietly keep using the app while showing an error.
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return false;
    setState(() {
      _loading = false;
      _blockedByDeviceLabel = result.existingDeviceLabel ?? 'another device';
    });
    return false;
  }

  /// Best-effort human label for this device, shown to the owner on
  /// the *other* device as "signed in on <label>" -- not a security
  /// boundary, just context. Platform-only (no device_info_plus
  /// dependency) since exact model name isn't worth a new package here.
  String _deviceLabel() {
    if (kIsWeb) return 'a web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'an Android device',
      TargetPlatform.iOS => 'an iPhone/iPad',
      TargetPlatform.windows => 'a Windows PC',
      TargetPlatform.macOS => 'a Mac',
      TargetPlatform.linux => 'a Linux device',
      _ => 'another device',
    };
  }

  /// Re-signs in with the same credentials and forces the claim,
  /// evicting whatever device currently holds it. Reuses the password
  /// already typed in -- if the person navigated away and it's been
  /// cleared, this just surfaces the normal "enter password" error via
  /// _submit()'s existing empty-field check.
  Future<void> _forceSignOutOtherDevice() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      await _claimThisDevice(force: true);
      if (!mounted) return;
      setState(() {
        _blockedByDeviceLabel = null;
        _loading = false;
      });
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
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
      // Explicit (it's the default) so the body always shrinks when the
      // keyboard opens instead of the keyboard covering the fields.
      resizeToAvoidBottomInset: true,
      body: Center(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/branding/logo.png',
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'MERQ',
                    style: AppTextStyles.mono(size: 18, weight: FontWeight.w700, color: AppColors.ledAmber, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isSignIn ? 'SIGN IN TO YOUR STORE' : 'SET UP YOUR STORE',
                    style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 2),
                  ),
                  const SizedBox(height: 28),
                  if (!_isSignIn) ...[
                    _SetupField(label: 'Store Name', controller: _storeNameCtrl, hint: 'e.g. Sunrise Café'),
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
                  if (_blockedByDeviceLabel != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'This account is already signed in on ${_blockedByDeviceLabel!}. '
                      'Sign out there first, or force it out below.',
                      style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading ? null : _forceSignOutOtherDevice,
                      child: Text(
                        'Force sign out other device and continue',
                        style: AppTextStyles.body(size: 12.5, weight: FontWeight.w700, color: AppColors.ledAmber),
                      ),
                    ),
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
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(_kPrivacyPolicyUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      'Privacy Policy',
                      style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
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
/// redirectTo points at reset-password.html, hosted alongside
/// privacy.html and delete-account.html on merq.prohubapps.com --
/// same branded card style as this dialog. The user finishes the
/// reset in the browser, then comes back and signs in in the app;
/// that URL must also be whitelisted in Supabase under
/// Authentication -> URL Configuration -> Redirect URLs, or the
/// reset link in the email will be rejected.
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
        redirectTo: 'https://merq.prohubapps.com/reset-password.html',
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

class _SetupField extends StatefulWidget {
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
  State<_SetupField> createState() => _SetupFieldState();
}

class _SetupFieldState extends State<_SetupField> {
  // Starts obscured whenever the field is a password field at all —
  // only flips to visible if the person taps the eye icon below.
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.mono(size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          obscureText: widget.obscure && _obscured,
          // When this field gains focus, Flutter scrolls it into view
          // keeping this much clearance from the edges. The default (20)
          // leaves the password field flush against the keyboard, and
          // the button/error text below it hidden. The large bottom
          // value lifts it clear so the field and its show/hide icon
          // stay visible while typing.
          scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 160),
          style: AppTextStyles.body(size: 14),
          decoration: InputDecoration(
            hintText: widget.hint,
            // Only a password-type field gets the toggle — Store
            // Name/Email/etc. pass obscure: false and never show it.
            suffixIcon: widget.obscure
                ? IconButton(
                    icon: Icon(
                      _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
          onSubmitted: widget.onSubmit == null ? null : (_) => widget.onSubmit!(),
        ),
      ],
    );
  }
}
