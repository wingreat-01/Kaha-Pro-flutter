import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import '../state/currency_provider.dart';
import '../state/ingredient_provider.dart';
import '../state/product_provider.dart';
import '../state/recipe_provider.dart';
import '../state/transaction_provider.dart';
import '../state/user_provider.dart';
import '../theme/app_theme.dart';

/// Opens the Void sale dialog for [transaction]. Resolves to true when
/// the sale was voided (and its stock put back), false/null otherwise.
///
/// Anyone can open this, but it only succeeds with an ADMIN's name + PIN,
/// checked server-side by void_transaction(). An admin voids with their
/// own PIN; a cashier needs an admin to type theirs on this device
/// ("manager override") — the void is then recorded under that admin.
Future<bool?> showVoidSaleDialog(
  BuildContext context, {
  required Transaction transaction,
  required AppUser currentUser,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    barrierDismissible: false,
    builder: (_) => _VoidSaleDialog(transaction: transaction, currentUser: currentUser),
  );
}

const _reasons = [
  'Wrong item',
  'Customer cancelled',
  'Wrong payment',
  'Duplicate sale',
  'Other',
];

class _VoidSaleDialog extends StatefulWidget {
  final Transaction transaction;
  final AppUser currentUser;

  const _VoidSaleDialog({required this.transaction, required this.currentUser});

  @override
  State<_VoidSaleDialog> createState() => _VoidSaleDialogState();
}

class _VoidSaleDialogState extends State<_VoidSaleDialog> {
  final _noteController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _pinController = TextEditingController();
  String? _reason;
  String? _selectedAdmin;
  bool _submitting = false;
  String? _error;

  bool get _isAdmin => widget.currentUser.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _selectedAdmin = widget.currentUser.name;
    } else {
      // Cashier override: offer the store's admins to pick from. The
      // Users list is normally only loaded by Settings → Users, which a
      // cashier never opens.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final users = context.read<UserProvider>();
        if (users.users.isEmpty && !users.loading) users.loadFromSupabase();
      });
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _adminNameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String? get _fullReason {
    if (_reason == null) return null;
    final note = _noteController.text.trim();
    if (_reason == 'Other') return note.isEmpty ? null : note;
    return note.isEmpty ? _reason : '$_reason: $note';
  }

  String get _adminName => (_selectedAdmin ?? _adminNameController.text).trim();

  Future<void> _submit() async {
    final reason = _fullReason;
    if (reason == null) {
      setState(() => _error = _reason == 'Other' ? 'Describe why this sale is being voided.' : 'Choose a reason.');
      return;
    }
    if (_adminName.isEmpty) {
      setState(() => _error = 'Choose the admin approving this void.');
      return;
    }
    if (_pinController.text.isEmpty) {
      setState(() => _error = 'Enter the admin\'s PIN.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final transactions = context.read<TransactionProvider>();
    final products = context.read<ProductProvider>();
    final recipes = context.read<RecipeProvider>();
    final ingredients = context.read<IngredientProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final Transaction voided;
    try {
      voided = await transactions.voidTransaction(
        widget.transaction,
        adminName: _adminName,
        pin: _pinController.text,
        reason: reason,
      );
    } on VoidTransactionException catch (e) {
      if (!mounted) return;
      _pinController.clear();
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      return;
    }

    // The void itself is committed at this point; putting stock back is
    // best-effort, so a failure here is reported but doesn't undo it.
    var unitProducts = const <String>[];
    var restockFailed = false;
    try {
      unitProducts = await products.restockForVoid(
        voided.items,
        reference: voided.transactionNumber,
        staffName: voided.voidedByName,
      );
      final restock = await recipes.computeDeductionsForLineItems(voided.items);
      await ingredients.restockForVoid(
        restock,
        reference: voided.transactionNumber,
        staffName: voided.voidedByName,
      );
    } catch (e) {
      debugPrint('Restock after void ${voided.transactionNumber} failed: $e');
      restockFailed = true;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);

    final parts = <String>['${voided.transactionNumber} voided.'];
    if (restockFailed) {
      parts.add('Some stock could not be put back — check Inventory.');
    } else if (unitProducts.isNotEmpty) {
      parts.add('Barcoded units of ${unitProducts.toSet().join(', ')} stay marked sold — re-add them with Add units.');
    }
    messenger.showSnackBar(SnackBar(
      content: Text(parts.join(' '), style: AppTextStyles.body(size: 13)),
      duration: Duration(seconds: parts.length > 1 ? 8 : 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final txn = widget.transaction;
    final admins = _isAdmin
        ? const <AppUser>[]
        : context.watch<UserProvider>().users.where((u) => u.role == UserRole.admin).toList();

    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text(
        'Void ${txn.transactionNumber}?',
        style: AppTextStyles.body(size: 16, weight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${context.money(txn.total)} · ${txn.itemCount} item${txn.itemCount == 1 ? '' : 's'}. '
                'The sale stays in history marked VOIDED, is left out of totals and reports, '
                'and its stock is put back. This can\'t be undone.',
                style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              _label('REASON'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in _reasons)
                    ChoiceChip(
                      label: Text(r),
                      selected: _reason == r,
                      onSelected: _submitting ? null : (_) => setState(() => _reason = r),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                enabled: !_submitting,
                maxLength: 120,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _reason == 'Other' ? 'Describe the reason (required)' : 'Note (optional)',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              _label(_isAdmin ? 'APPROVED BY' : 'ADMIN APPROVAL'),
              if (_isAdmin)
                Text(widget.currentUser.name, style: AppTextStyles.body(size: 14, weight: FontWeight.w600))
              else if (admins.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedAdmin,
                  isDense: true,
                  dropdownColor: AppColors.slate,
                  hint: const Text('Choose an admin'),
                  items: [
                    for (final a in admins) DropdownMenuItem(value: a.name, child: Text(a.name)),
                  ],
                  onChanged: _submitting ? null : (v) => setState(() => _selectedAdmin = v),
                )
              else
                // Users list couldn't load (or is still loading) — the
                // server check is by name anyway, so typing it works too.
                TextField(
                  controller: _adminNameController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(isDense: true, hintText: 'Admin name'),
                ),
              if (!_isAdmin) ...[
                const SizedBox(height: 4),
                Text(
                  'Cashiers can\'t void sales. Ask an admin to enter their PIN below.',
                  style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _pinController,
                enabled: !_submitting,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 12,
                decoration: const InputDecoration(isDense: true, labelText: 'Admin PIN', counterText: ''),
                onSubmitted: (_) => _submitting ? null : _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.ledgerRed),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Void sale'),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: AppTextStyles.mono(size: 10, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1),
        ),
      );
}
