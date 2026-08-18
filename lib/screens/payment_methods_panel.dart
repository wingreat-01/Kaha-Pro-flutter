import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/payment_method.dart';
import '../theme/app_theme.dart';
import '../state/payment_method_provider.dart';
import '../widgets/bounded_content.dart';

/// Payment Methods admin panel — reached via Settings → Payment Methods.
/// Same pattern as CategoriesPanel: a stored list the owner/staff can
/// add to, rename, and delete. Unlike categories there's no protected
/// fallback bucket, but each method has an is_active toggle so a store
/// can temporarily disable a method (e.g. GCash is down) without
/// losing its transaction history — deleting a method is separate and
/// permanent.
class PaymentMethodsPanel extends StatelessWidget {
  const PaymentMethodsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PaymentMethodProvider>();
    final methods = [...provider.paymentMethods]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('Payment Methods', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ledAmber,
        foregroundColor: AppColors.charcoal,
        onPressed: () => _showPaymentMethodForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add payment method'),
      ),
      body: BoundedContent(
        child: methods.isEmpty
            ? Center(
                child: Text(
                  'No payment methods yet',
                  style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: methods.length,
                itemBuilder: (context, i) => _PaymentMethodRow(method: methods[i]),
              ),
      ),
    );
  }

  static void _showPaymentMethodForm(BuildContext context, {PaymentMethod? existing}) {
    showDialog(
      context: context,
      builder: (_) => _PaymentMethodFormDialog(existing: existing),
    );
  }
}

class _PaymentMethodRow extends StatelessWidget {
  final PaymentMethod method;
  const _PaymentMethodRow({required this.method});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => PaymentMethodsPanel._showPaymentMethodForm(context, existing: method),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.slateField,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slateBorder, width: 1),
                ),
                child: Icon(
                  Icons.payments_outlined,
                  size: 18,
                  color: method.isActive ? AppColors.ledAmber : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.name,
                      style: AppTextStyles.body(
                        size: 14,
                        weight: FontWeight.w600,
                        color: method.isActive ? null : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      method.isActive ? 'Active — shown at checkout' : 'Disabled — hidden at checkout',
                      style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: method.isActive,
                activeColor: AppColors.tillGreen,
                onChanged: (value) =>
                    context.read<PaymentMethodProvider>().setActive(method.id, value),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: AppColors.ledgerRed),
                onPressed: () => _confirmDelete(context, method),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, PaymentMethod method) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text('Delete payment method?', style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
        content: Text(
          'Delete "${method.name}"? Past transactions that used it keep their record either way — this only removes it from checkout going forward.',
          style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: AppTextStyles.body(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              context.read<PaymentMethodProvider>().deletePaymentMethod(method.id);
              Navigator.of(dialogContext).pop();
            },
            child: Text('Delete', style: AppTextStyles.body(color: AppColors.ledgerRed, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Add/rename form. `existing` null means "add new"; non-null means
/// rename that payment method (its active state and sort order are
/// left untouched — this dialog only ever changes the name).
class _PaymentMethodFormDialog extends StatefulWidget {
  final PaymentMethod? existing;
  const _PaymentMethodFormDialog({this.existing});

  @override
  State<_PaymentMethodFormDialog> createState() => _PaymentMethodFormDialogState();
}

class _PaymentMethodFormDialogState extends State<_PaymentMethodFormDialog> {
  late final TextEditingController _nameController;
  String? _error;
  bool _submitting = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final provider = context.read<PaymentMethodProvider>();

    if (name.isEmpty) {
      setState(() => _error = 'Payment method name is required.');
      return;
    }
    final isDuplicate = provider.paymentMethods.any(
      (m) => m.name.toLowerCase() == name.toLowerCase() && m.id != widget.existing?.id,
    );
    if (isDuplicate) {
      setState(() => _error = 'A payment method with that name already exists.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final success = _isEditing
        ? await provider.updatePaymentMethod(widget.existing!.copyWith(name: name))
        : await provider.addPaymentMethod(name);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _submitting = false;
        _error = provider.error ?? 'Something went wrong. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text(
        _isEditing ? 'Rename payment method' : 'Add payment method',
        style: AppTextStyles.body(size: 16, weight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            enabled: !_submitting,
            style: AppTextStyles.body(size: 14),
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. GCash, Maya, Bank Transfer'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _submitting ? null : _submit,
          child: Text(
            _isEditing ? 'Save' : 'Add',
            style: AppTextStyles.body(color: AppColors.ledAmber, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
