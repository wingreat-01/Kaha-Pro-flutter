import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/order_table.dart';
import '../state/table_provider.dart';
import '../widgets/bounded_content.dart';
import 'table_qr_screen.dart';

/// Tables admin panel — reached via Settings → Tables. Lists this
/// store's tables (label + a chevron into that table's QR code),
/// backed by Supabase's `tables` table via TableProvider. Deleting a
/// table isn't exposed here yet — TableProvider.deactivateTable
/// exists for when that's wanted, same soft-delete shape as Users.
class TablesPanel extends StatefulWidget {
  const TablesPanel({super.key});

  @override
  State<TablesPanel> createState() => _TablesPanelState();
}

class _TablesPanelState extends State<TablesPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TableProvider>().loadFromSupabase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TableProvider>();
    final tables = provider.tables;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('Tables', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ledAmber,
        foregroundColor: AppColors.charcoal,
        onPressed: () => showDialog(context: context, builder: (_) => const _AddTableDialog()),
        icon: const Icon(Icons.add),
        label: const Text('Add table'),
      ),
      body: BoundedContent(
        child: provider.loading && tables.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : provider.error != null && tables.isEmpty
                ? Center(
                    child: Text(
                      provider.error!,
                      style: AppTextStyles.body(size: 14, color: AppColors.ledgerRed),
                    ),
                  )
                : tables.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No tables yet — add one to generate its QR ordering code.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => context.read<TableProvider>().loadFromSupabase(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: tables.length,
                          itemBuilder: (context, i) => _TableRow(table: tables[i]),
                        ),
                      ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final OrderTable table;
  const _TableRow({required this.table});

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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TableQrScreen(table: table)),
        ),
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
                child: Icon(Icons.qr_code_2, size: 18, color: AppColors.ledAmber),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(table.label, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTableDialog extends StatefulWidget {
  const _AddTableDialog();

  @override
  State<_AddTableDialog> createState() => _AddTableDialogState();
}

class _AddTableDialogState extends State<_AddTableDialog> {
  final _labelController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Table name is required.');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      await context.read<TableProvider>().addTable(label);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DuplicateTableLabelException
            ? e.message
            : 'Something went wrong adding this table. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text('Add table', style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _labelController,
            style: AppTextStyles.body(size: 14),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Table name (e.g. Table 5)'),
            onSubmitted: (_) => _saving ? null : _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Add', style: AppTextStyles.body(color: AppColors.ledAmber, weight: FontWeight.w700)),
        ),
      ],
    );
  }
}
