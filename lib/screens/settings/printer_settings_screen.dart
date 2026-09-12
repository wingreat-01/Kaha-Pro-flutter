import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/printer_config.dart';
import '../../state/printer_provider.dart';
import '../../theme/app_theme.dart';

/// Reached from Settings — "Receipt Printer". Lets the owner/cashier
/// connect a Bluetooth or WiFi/network thermal printer, test it, and
/// see/remove whatever's currently saved on this device.
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterConnectionType _selectedType = PrinterConnectionType.network;
  List<PrinterConfig> _bluetoothResults = [];
  bool _scanning = false;

  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  final _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill from whatever's already saved, so re-opening this
    // screen to tweak a printer doesn't start from a blank form.
    final saved = context.read<PrinterProvider>().savedPrinter;
    if (saved != null) {
      _selectedType = saved.type;
      _labelController.text = saved.name;
      if (saved.type == PrinterConnectionType.network) {
        _ipController.text = saved.address;
        _portController.text = saved.port.toString();
      }
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final results = await context.read<PrinterProvider>().scanBluetoothPrinters();
    if (!mounted) return;
    setState(() {
      _bluetoothResults = results;
      _scanning = false;
    });
  }

  Future<void> _saveNetworkPrinter() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the printer\'s IP address.')));
      return;
    }
    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    final config = PrinterConfig(
      type: PrinterConnectionType.network,
      name: _labelController.text.trim().isEmpty ? ip : _labelController.text.trim(),
      address: ip,
      port: port,
    );
    await context.read<PrinterProvider>().savePrinter(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Printer saved.')));
  }

  Future<void> _saveBluetoothPrinter(PrinterConfig device) async {
    await context.read<PrinterProvider>().savePrinter(device);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${device.name} saved as your printer.')));
  }

  Future<void> _testPrint() async {
    final provider = context.read<PrinterProvider>();
    final saved = provider.savedPrinter;
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save a printer first.')));
      return;
    }
    final ok = await provider.testPrint(saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Test print sent.' : (provider.lastError ?? 'Test print failed.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrinterProvider>();
    final saved = provider.savedPrinter;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(title: const Text('Receipt Printer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (saved != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.slateField,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slateBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      saved.type == PrinterConnectionType.bluetooth ? Icons.bluetooth : Icons.wifi,
                      color: AppColors.ledAmber,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(saved.name, style: AppTextStyles.body(size: 14, weight: FontWeight.w700)),
                          Text(
                            saved.type == PrinterConnectionType.bluetooth
                                ? saved.address
                                : '${saved.address}:${saved.port}',
                            style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.read<PrinterProvider>().clearPrinter(),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: provider.status == PrinterConnectionStatus.printing ? null : _testPrint,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.slateBorder),
                  ),
                  child: provider.status == PrinterConnectionStatus.printing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test print'),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              'ADD A PRINTER',
              style: AppTextStyles.mono(
                size: 11,
                weight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TypeTab(
                    label: 'WiFi / Network',
                    selected: _selectedType == PrinterConnectionType.network,
                    onTap: () => setState(() => _selectedType = PrinterConnectionType.network),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeTab(
                    label: 'Bluetooth',
                    selected: _selectedType == PrinterConnectionType.bluetooth,
                    onTap: () => setState(() => _selectedType = PrinterConnectionType.bluetooth),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_selectedType == PrinterConnectionType.network) ...[
              TextField(
                controller: _labelController,
                style: AppTextStyles.body(size: 13),
                decoration: const InputDecoration(labelText: 'Label (optional)', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(size: 13),
                decoration: const InputDecoration(
                  labelText: 'Printer IP address',
                  hintText: '192.168.1.50',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(size: 13),
                decoration: const InputDecoration(labelText: 'Port', hintText: '9100', isDense: true),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveNetworkPrinter,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.tillGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save printer'),
                ),
              ),
            ] else ...[
              Text(
                'Pair the printer in your phone\'s Bluetooth settings first, then scan below.',
                style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _scanning ? null : _scan,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.slateBorder),
                  ),
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(_scanning ? 'Scanning…' : 'Scan paired devices'),
                ),
              ),
              const SizedBox(height: 12),
              for (final device in _bluetoothResults)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.print_outlined, color: AppColors.textPrimary),
                  title: Text(device.name, style: AppTextStyles.body(size: 13, weight: FontWeight.w600)),
                  subtitle: Text(device.address, style: AppTextStyles.body(size: 11, color: AppColors.textSecondary)),
                  trailing: TextButton(
                    onPressed: () => _saveBluetoothPrinter(device),
                    child: const Text('Use this'),
                  ),
                ),
              if (!_scanning && _bluetoothResults.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No paired printers found yet.',
                    style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.ledAmber.withOpacity(0.15) : AppColors.slateField,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.ledAmber : AppColors.slateBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.mono(
            size: 12,
            weight: FontWeight.w700,
            color: selected ? AppColors.ledAmber : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
