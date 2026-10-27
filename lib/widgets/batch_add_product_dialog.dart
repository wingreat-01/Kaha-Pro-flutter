import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../state/product_provider.dart';
import '../theme/app_theme.dart';
import '../services/scan_sounds.dart';
import 'barcode_scanner_screen.dart';

/// Batch entry for items where every unit has its own barcode.
///
/// New product: fill in brand / product name / model no. / price /
/// category, then scan every unit (camera, or a USB/Bluetooth scanner
/// typing into the scan field). One product is created with a stock
/// count equal to the number of units scanned.
///
/// Existing product ([existingProduct] set): only the scanning part is
/// shown, to receive more units of a product that already tracks units.
///
/// [onSubmit] does the saving and may throw; the dialog shows the
/// message inline and stays open.
class BatchAddProductDialog extends StatefulWidget {
  final List<String> existingCategories;
  final String? initialCategory;
  final Product? existingProduct;

  /// Returns a ready-to-show message when [code] is already used by a
  /// product or unit (ProductProvider.barcodeConflict), else null.
  final String? Function(String code) barcodeConflict;

  final Future<void> Function({
    required String name,
    required double price,
    required String category,
    required List<String> barcodes,
  }) onSubmit;

  const BatchAddProductDialog({
    super.key,
    required this.existingCategories,
    required this.barcodeConflict,
    required this.onSubmit,
    this.initialCategory,
    this.existingProduct,
  });

  @override
  State<BatchAddProductDialog> createState() => _BatchAddProductDialogState();
}

class _BatchAddProductDialogState extends State<BatchAddProductDialog> {
  static const String _newCategoryKey = '\u0000new';

  final _brandCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();

  final List<String> _codes = [];
  String? _category;
  String? _error; // form-level error
  String? _scanMessage; // last scan problem (duplicate etc.)
  bool _saving = false;

  bool get _isRestock => widget.existingProduct != null;

  @override
  void initState() {
    super.initState();
    final cats = widget.existingCategories.toSet().toList();
    final initial = widget.initialCategory;
    _category = (initial != null && cats.contains(initial))
        ? initial
        : (cats.isNotEmpty ? cats.first : _newCategoryKey);
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _nameCtrl.dispose();
    _modelCtrl.dispose();
    _priceCtrl.dispose();
    _newCategoryCtrl.dispose();
    _scanCtrl.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  String get _composedName => [_brandCtrl.text, _nameCtrl.text, _modelCtrl.text]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' ');

  /// Adds one scanned/typed code. Returns an error message, or null on
  /// success. Shared by the text field and the camera.
  String? _addCode(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return null;
    final normalized = Product.normalizeBarcode(code);
    if (_codes.any((c) => Product.normalizeBarcode(c) == normalized)) {
      return '$code was already scanned in this batch.';
    }
    final conflict = widget.barcodeConflict(code);
    if (conflict != null) return conflict;
    setState(() {
      _codes.add(code);
      _error = null;
    });
    return null;
  }

  void _onScanSubmitted(String value) {
    final problem = _addCode(value);
    if (value.trim().isNotEmpty) {
      ScanSounds.play(problem == null ? ScanSound.success : ScanSound.duplicate);
    }
    setState(() => _scanMessage = problem);
    _scanCtrl.clear();
    _scanFocus.requestFocus(); // ready for the next unit
  }

  Future<void> _openCamera() async {
    await BarcodeScannerScreen.scanContinuously(
      context,
      title: 'Scan each unit',
      onScan: (ctx, code) async {
        final problem = _addCode(code);
        return problem == null
            ? ScanFeedback.ok('Unit ${_codes.length} added')
            : ScanFeedback.fail(problem, sound: ScanSound.duplicate);
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    String name;
    double price;
    String category;
    if (_isRestock) {
      final p = widget.existingProduct!;
      name = p.name;
      price = p.price;
      category = p.category;
    } else {
      name = _composedName;
      price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
      category = _category == _newCategoryKey ? _newCategoryCtrl.text.trim() : (_category ?? '');
      if (name.isEmpty) {
        setState(() => _error = 'Enter a brand or product name.');
        return;
      }
      if (price <= 0) {
        setState(() => _error = 'Enter a valid price.');
        return;
      }
      if (category.isEmpty) {
        setState(() => _error = 'Pick or enter a category.');
        return;
      }
    }
    if (_codes.isEmpty) {
      setState(() => _error = 'Scan at least one unit.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(name: name, price: price, category: category, barcodes: List.of(_codes));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = (e is DuplicateBarcodeException || e is ProductLimitExceededException)
            ? e.toString()
            : "Couldn't save — try again";
      });
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: AppTextStyles.mono(
                size: 10, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 1)),
      );

  Widget _field(String label, TextEditingController c,
      {String? hint, TextInputType? keyboardType, ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          controller: c,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: AppTextStyles.body(size: 14),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const maxDialogWidth = 560.0;
    const minSideMargin = 8.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalInset = screenWidth > maxDialogWidth + (minSideMargin * 2)
        ? (screenWidth - maxDialogWidth) / 2
        : minSideMargin;
    final categories = widget.existingCategories.toSet().toList();

    return Dialog(
      backgroundColor: AppColors.slate,
      insetPadding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isRestock ? 'ADD UNITS' : 'ADD PRODUCT IN BATCH',
                style: AppTextStyles.mono(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 14),
              if (_isRestock)
                Text(widget.existingProduct!.name,
                    style: AppTextStyles.body(size: 15, weight: FontWeight.w700))
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field('Brand', _brandCtrl,
                          hint: 'e.g. Ingco', onChanged: (_) => setState(() {})),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field('Model no.', _modelCtrl,
                          hint: 'e.g. CDLI12411', onChanged: (_) => setState(() {})),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _field('Product name', _nameCtrl,
                    hint: 'e.g. Wireless Drill', onChanged: (_) => setState(() {})),
                if (_composedName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Saved as: $_composedName',
                      style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 12),
                _field('Price (each)', _priceCtrl,
                    hint: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 12),
                _label('Category'),
                DropdownButtonFormField<String>(
                  value: _category,
                  dropdownColor: AppColors.slate,
                  style: AppTextStyles.body(size: 14),
                  decoration: const InputDecoration(),
                  items: [
                    ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    const DropdownMenuItem(value: _newCategoryKey, child: Text('＋ New category…')),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
                if (_category == _newCategoryKey) ...[
                  const SizedBox(height: 10),
                  _field('', _newCategoryCtrl, hint: 'New category name'),
                ],
              ],
              const SizedBox(height: 18),
              _label('SCAN UNITS  •  ${_codes.length} scanned'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _scanCtrl,
                      focusNode: _scanFocus,
                      autofocus: kIsWeb, // laptop + USB scanner: ready to scan
                      style: AppTextStyles.body(size: 14),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _onScanSubmitted,
                      decoration: const InputDecoration(
                        hintText: 'Scan with a barcode scanner, or type a code + Enter',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Scan with camera',
                    icon: Icon(Icons.qr_code_scanner, color: AppColors.ledAmber),
                    onPressed: _saving ? null : _openCamera,
                  ),
                ],
              ),
              if (_scanMessage != null) ...[
                const SizedBox(height: 6),
                Text(_scanMessage!, style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
              ],
              if (_codes.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 210),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.charcoal,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _codes.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Text('${i + 1}',
                            style: AppTextStyles.mono(size: 12, color: AppColors.textMuted)),
                        title: Text(_codes[i], style: AppTextStyles.mono(size: 13)),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: Icon(Icons.close, size: 16, color: AppColors.textMuted),
                          onPressed: _saving ? null : () => setState(() => _codes.removeAt(i)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTextStyles.body(size: 12.5, color: AppColors.ledgerRed)),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_codes.isEmpty
                            ? (_isRestock ? 'Add units' : 'Save')
                            : (_isRestock
                                ? 'Add ${_codes.length} unit${_codes.length == 1 ? '' : 's'}'
                                : 'Save ${_codes.length} unit${_codes.length == 1 ? '' : 's'}')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
