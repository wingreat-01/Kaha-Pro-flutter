import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

/// Settings → Delete Account. Calls the delete-account Edge Function,
/// which does the actual cascade (see supabase/functions/delete-account
/// for what gets removed). This screen's only job is: explain what's
/// about to happen, make the person type DELETE to confirm they mean
/// it, call the function, then sign out of the local Supabase session
/// so the app falls back to StoreSetupScreen.
///
/// [onAccountDeleted] is the same shape as HomeShell's existing
/// onLogout callback (clears the PIN-level _loggedInUser session in
/// _KahaproAppState) -- it must be threaded down through SettingsPanel
/// from wherever HomeShell is built, since Supabase.auth.signOut()
/// alone does NOT do this (see main.dart's own comment on onLogout:
/// signing out of Supabase does not clear the PIN session, and this
/// screen needs both cleared for the app to actually land back on
/// StoreSetupScreen instead of showing a signed-out HomeShell).
class DeleteAccountScreen extends StatefulWidget {
  final VoidCallback onAccountDeleted;
  const DeleteAccountScreen({super.key, required this.onAccountDeleted});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _deleting = false;
  String? _error;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_deleting,
      builder: (dialogContext) => _DeleteConfirmDialog(),
    );
    if (confirmed != true) return;

    setState(() {
      _deleting = true;
      _error = null;
    });

    try {
      // functions.invoke automatically attaches the current session's
      // access token as the Authorization header -- exactly what
      // delete-account/index.ts verifies via auth.getUser(token).
      final res = await Supabase.instance.client.functions.invoke('delete-account');

      if (res.status != 200) {
        final body = res.data;
        final message = (body is Map && body['error'] is String)
            ? body['error'] as String
            : 'Could not delete account. Try again or contact support.';
        if (!mounted) return;
        setState(() {
          _deleting = false;
          _error = message;
        });
        return;
      }

      // Server-side deletion succeeded. Clear the local Supabase
      // session (the deleted user's old access token would otherwise
      // keep looking "signed in" client-side until it naturally
      // expires), then clear the PIN-level session via the callback
      // so the app actually falls back to StoreSetupScreen.
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      widget.onAccountDeleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Something went wrong. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(title: const Text('Delete Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.slateField,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.ledgerRed.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.ledgerRed, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This permanently deletes your account and cannot be undone.',
                      style: AppTextStyles.body(size: 14, weight: FontWeight.w600, color: AppColors.ledgerRed),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Deleting your account will permanently remove:',
              style: AppTextStyles.body(size: 14, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const _DeleteBullet('Your store profile and settings'),
            const _DeleteBullet('All products, categories and ingredients'),
            const _DeleteBullet('All staff accounts and PINs'),
            const _DeleteBullet('Your complete sales and transaction history'),
            const _DeleteBullet('Payment methods and receipt settings'),
            const SizedBox(height: 8),
            Text(
              'If other people are also members of your store, only your own access is removed and the store keeps running for them.',
              style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 20),
              Text(
                _error!,
                style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed, weight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _deleting ? null : _confirmAndDelete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ledgerRed,
                  foregroundColor: Colors.white,
                ),
                child: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Delete my account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBullet extends StatelessWidget {
  final String text;
  const _DeleteBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: AppTextStyles.body(size: 13.5, color: AppColors.textSecondary)),
          Expanded(
            child: Text(text, style: AppTextStyles.body(size: 13.5, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Type-to-confirm dialog -- requires typing DELETE (case-sensitive)
/// before the destructive button enables, same pattern used by GitHub/
/// GitLab repo deletion. A plain Yes/No dialog is too easy to
/// reflexively tap through on something this irreversible.
class _DeleteConfirmDialog extends StatefulWidget {
  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _controller = TextEditingController();
  bool _canConfirm = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: const Text('Are you sure?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Type DELETE below to confirm. This cannot be undone.',
            style: AppTextStyles.body(size: 13.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'DELETE'),
            onChanged: (value) => setState(() => _canConfirm = value.trim() == 'DELETE'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canConfirm ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.ledgerRed,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
