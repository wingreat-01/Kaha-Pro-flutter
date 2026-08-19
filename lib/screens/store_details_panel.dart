import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/store_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';

/// Store Details screen — reached from Settings > Store details. Edits
/// the store's name, address, and receipt footer message (the last
/// printed/shown at the bottom of a receipt once receipt rendering
/// reads it). All three live on the `stores` row itself (see
/// 007_store_details.sql), same as business_type/plan.
class StoreDetailsPanel extends StatefulWidget {
  const StoreDetailsPanel({super.key});

  @override
  State<StoreDetailsPanel> createState() => _StoreDetailsPanelState();
}

class _StoreDetailsPanelState extends State<StoreDetailsPanel> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _footerController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final store = context.read<StoreProvider>().store;
    _nameController = TextEditingController(text: store?.name ?? '');
    _addressController = TextEditingController(text: store?.address ?? '');
    _footerController = TextEditingController(text: store?.receiptFooter ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Store name can\'t be empty.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    // Empty text fields are saved as null (cleared), not as empty
    // strings — keeps "never set" and "set then cleared" both reading
    // the same way everywhere else that checks store.address /
    // store.receiptFooter for null.
    final address = _addressController.text.trim();
    final footer = _footerController.text.trim();

    try {
      await context.read<StoreProvider>().updateStoreDetails(
            name: name,
            address: address.isEmpty ? null : address,
            receiptFooter: footer.isEmpty ? null : footer,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save — check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store details'),
      ),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FieldLabel('STORE NAME'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. Kahapro Store'),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 20),
            _FieldLabel('ADDRESS'),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              style: AppTextStyles.body(size: 14),
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Street, barangay, city'),
            ),
            const SizedBox(height: 20),
            _FieldLabel('RECEIPT FOOTER'),
            const SizedBox(height: 4),
            Text(
              'Shown at the bottom of every printed receipt.',
              style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _footerController,
              style: AppTextStyles.body(size: 14),
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'e.g. Thank you for shopping with us!'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed, weight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.tillGreen,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.mono(size: 11, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.5),
    );
  }
}
