import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/ingredient_provider.dart';
import '../state/product_provider.dart';
import '../state/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';

/// Read-only history of everything going out of / coming into stock --
/// reached from Settings -> Inventory -> Inventory Movements.
///
/// Nothing here has its own records. It stitches together three
/// existing sources:
///   * Supplies & Materials -- ingredient_stock_movements (manual
///     withdrawals/restocks, plus sale-driven usage from recipes).
///   * Products, manual changes -- product_stock_movements (the +/-
///     buttons and stock counts in Inventory).
///   * Products, sales -- read straight from Transactions (already in
///     memory), for products with Track stock on. Sales are not copied
///     into a second log.
///
/// Direction is the sign of the change: stock going OUT is a
/// Withdrawal, stock coming IN is Receiving.

const int _kSourceLimit = 1000;
const String _kAllUnits = 'All Units';
const double _kTableBreakpoint = 820;

enum MovementType { withdrawal, receiving }

class InventoryMovement {
  final String id;
  final DateTime date;
  final String itemName;
  final String? variantName;
  final double quantity; // always positive -- direction is [type]
  final String unit;
  final MovementType type;
  final String reason;
  final String? reference;
  final String? user;

  const InventoryMovement({
    required this.id,
    required this.date,
    required this.itemName,
    this.variantName,
    required this.quantity,
    required this.unit,
    required this.type,
    required this.reason,
    this.reference,
    this.user,
  });

  bool get isReceiving => type == MovementType.receiving;
}

String _trimZeros(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) =>
    '${_two(d.month)}/${_two(d.day)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _shortDate(DateTime d, {required bool withYear}) =>
    '${_months[d.month - 1]} ${d.day}${withYear ? ', ${d.year}' : ''}';

/// Ingredients store the raw unit code ('ml'); products already show
/// 'mL'. Normalising here keeps the Unit filter from listing both.
String _normalizeUnit(String unit) => unit == 'ml' ? 'mL' : unit;

String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

class InventoryMovementsPanel extends StatefulWidget {
  const InventoryMovementsPanel({super.key});

  @override
  State<InventoryMovementsPanel> createState() => _InventoryMovementsPanelState();
}

class _InventoryMovementsPanelState extends State<InventoryMovementsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);
  final TextEditingController _searchCtrl = TextEditingController();

  late DateTimeRange _range = _defaultRange();
  String _unit = _kAllUnits;
  String _query = '';

  bool _loading = true;
  Object? _error;
  bool _truncated = false;
  List<InventoryMovement> _all = const [];

  /// Last 30 days, today included.
  static DateTimeRange _defaultRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: DateTime(today.year, today.month, today.day - 29), end: today);
  }

  @override
  void initState() {
    super.initState();
    // Deferred a frame: _load() calls setState, which isn't allowed
    // synchronously from initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ingredientProvider = context.read<IngredientProvider>();
    final productProvider = context.read<ProductProvider>();
    final transactionProvider = context.read<TransactionProvider>();

    final from = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final to = DateTime(_range.end.year, _range.end.month, _range.end.day + 1); // exclusive

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ingredientFuture =
          ingredientProvider.loadMovements(from: from, to: to, limit: _kSourceLimit);
      final productFuture =
          productProvider.loadMovements(from: from, to: to, limit: _kSourceLimit);
      await Future.wait([ingredientFuture, productFuture]);
      final ingredientRows = await ingredientFuture;
      final productRows = await productFuture;
      if (!mounted) return;

      final ingredientsById = {for (final i in ingredientProvider.ingredients) i.id: i};
      final productsById = {for (final p in productProvider.products) p.id: p};
      final movements = <InventoryMovement>[];

      // Supplies & Materials.
      for (final m in ingredientRows) {
        if (m.delta == 0) continue;
        final ingredient = ingredientsById[m.ingredientId];
        movements.add(InventoryMovement(
          id: 'ing-${m.id}',
          date: m.createdAt,
          itemName: ingredient?.name ?? 'Unknown item',
          quantity: m.delta.abs(),
          unit: ingredient == null ? '' : _normalizeUnit(ingredient.unitDisplay),
          type: m.delta > 0 ? MovementType.receiving : MovementType.withdrawal,
          reason: m.source == 'sale' ? 'Sale' : m.reason,
          reference: _clean(m.reference),
          user: _clean(m.staffName),
        ));
      }

      // Products -- manual changes.
      for (final m in productRows) {
        if (m.delta == 0) continue;
        movements.add(InventoryMovement(
          id: 'prod-${m.id}',
          date: m.createdAt,
          itemName: m.productName,
          quantity: m.delta.abs(),
          unit: _normalizeUnit(m.unit),
          type: m.delta > 0 ? MovementType.receiving : MovementType.withdrawal,
          reason: m.reason,
          user: _clean(m.staffName),
        ));
      }

      // Products -- sales, straight from Transactions. Only products
      // with Track stock on (the ones checkout actually deducts), and
      // only synced sales -- a still-queued sale hasn't moved stock yet.
      for (final t in transactionProvider.transactions) {
        if (t.isPending) continue;
        if (t.timestamp.isBefore(from) || !t.timestamp.isBefore(to)) continue;
        for (var i = 0; i < t.items.length; i++) {
          final item = t.items[i];
          if (item.productId.isEmpty) continue; // product deleted since
          final product = productsById[item.productId];
          if (product == null || !product.trackStock) continue;
          movements.add(InventoryMovement(
            id: 'sale-${t.id ?? t.localId ?? t.transactionNumber}-$i',
            date: t.timestamp,
            itemName: product.name,
            variantName: _clean(item.variantName),
            quantity: item.quantity.toDouble(),
            unit: _normalizeUnit(product.unitDisplay),
            type: MovementType.withdrawal,
            reason: 'Sale',
            reference: _clean(t.transactionNumber),
            user: _clean(t.cashierName),
          ));
        }
      }

      movements.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _all = movements;
        _truncated = ingredientRows.length >= _kSourceLimit || productRows.length >= _kSourceLimit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _load();
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _unit = _kAllUnits;
      _query = '';
    });
  }

  List<String> get _unitOptions {
    final units = {
      for (final m in _all)
        if (m.unit.isNotEmpty) m.unit,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_kAllUnits, ...units];
  }

  /// All three filters (tab type, unit, search) apply together.
  List<InventoryMovement> _filtered(MovementType? type, String unit) {
    final q = _query.trim().toLowerCase();
    return _all.where((m) {
      if (type != null && m.type != type) return false;
      if (unit != _kAllUnits && m.unit != unit) return false;
      if (q.isNotEmpty) {
        final haystack = [m.itemName, m.variantName ?? '', m.reference ?? '', m.user ?? '']
            .join(' ')
            .toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  String _rangeLabel() {
    final currentYear = DateTime.now().year;
    final withYear = _range.start.year != currentYear || _range.end.year != currentYear;
    return '${_shortDate(_range.start, withYear: withYear)} – ${_shortDate(_range.end, withYear: withYear)}';
  }

  @override
  Widget build(BuildContext context) {
    final unitOptions = _unitOptions;
    // If a date change removed the unit that was selected, fall back to
    // All Units rather than showing an empty list with no explanation.
    final unit = unitOptions.contains(_unit) ? _unit : _kAllUnits;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        elevation: 0,
        title: Text(
          'Inventory Movements',
          style: AppTextStyles.mono(size: 15, weight: FontWeight.w700, letterSpacing: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            color: AppColors.textSecondary,
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.ledAmber,
          labelColor: AppColors.ledAmber,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: AppTextStyles.mono(size: 12, weight: FontWeight.w700, letterSpacing: 1),
          unselectedLabelStyle: AppTextStyles.mono(size: 12, weight: FontWeight.w500, letterSpacing: 1),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Withdrawals'),
            Tab(text: 'Receiving'),
          ],
        ),
      ),
      body: BoundedContent(
        child: Column(
          children: [
            _buildFilters(unitOptions, unit),
            Expanded(child: _buildBody(unit)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(List<String> unitOptions, String unit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            style: AppTextStyles.body(size: 14),
            decoration: InputDecoration(
              hintText: 'Search item or reference…',
              prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textMuted),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 18, color: AppColors.textMuted),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: unit,
                  isExpanded: true,
                  dropdownColor: AppColors.slate,
                  style: AppTextStyles.body(size: 13),
                  decoration: const InputDecoration(),
                  items: [
                    for (final u in unitOptions)
                      DropdownMenuItem(value: u, child: Text(u, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => setState(() => _unit = value ?? _kAllUnits),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      _rangeLabel(),
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(size: 12.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.slateBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(String unit) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load inventory movements.",
                textAlign: TextAlign.center,
                style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed),
              ),
              const SizedBox(height: 4),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _load,
                child: Text(
                  'Retry',
                  style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildList(_filtered(null, unit), unit, emptyNoun: 'inventory movements'),
        _buildList(_filtered(MovementType.withdrawal, unit), unit, emptyNoun: 'withdrawals'),
        _buildList(_filtered(MovementType.receiving, unit), unit, emptyNoun: 'receiving records'),
      ],
    );
  }

  Widget _buildList(List<InventoryMovement> items, String unit, {required String emptyNoun}) {
    if (items.isEmpty) {
      final hasFilters = unit != _kAllUnits || _query.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasFilters
                    ? 'No movements match your filters.'
                    : 'No $emptyNoun in this date range.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
              ),
              if (hasFilters) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _clearFilters,
                  child: Text(
                    'Clear filters',
                    style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledAmber),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kTableBreakpoint;
        final banner = _truncated
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Showing the latest $_kSourceLimit records per source. Narrow the date range to see older ones.',
                  style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                ),
              )
            : const SizedBox.shrink();

        if (isWide) {
          return Column(
            children: [
              banner,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _MovementTable(items: items),
                ),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            if (_truncated)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Showing the latest $_kSourceLimit records per source. Narrow the date range to see older ones.',
                  style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                ),
              ),
            for (final m in items) _MovementCard(movement: m),
          ],
        );
      },
    );
  }
}

Color _typeColor(InventoryMovement m) => m.isReceiving ? AppColors.tillGreen : AppColors.ledgerRed;

class _TypeChip extends StatelessWidget {
  final InventoryMovement movement;
  const _TypeChip({required this.movement});

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(movement);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        movement.isReceiving ? 'RECEIVING' : 'WITHDRAWAL',
        style: AppTextStyles.mono(size: 10, weight: FontWeight.w700, color: color, letterSpacing: 1),
      ),
    );
  }
}

/// Phone-width layout: one card per movement.
class _MovementCard extends StatelessWidget {
  final InventoryMovement movement;
  const _MovementCard({required this.movement});

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final color = _typeColor(m);
    final sign = m.isReceiving ? '+' : '-';
    final qty = '$sign${_trimZeros(m.quantity)}${m.unit.isEmpty ? '' : ' ${m.unit}'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.itemName, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                    if (m.variantName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        m.variantName!,
                        style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(qty, style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _TypeChip(movement: m),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.reason,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(size: 12, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Text(_formatDate(m.date), style: AppTextStyles.body(size: 10.5, color: AppColors.textMuted)),
            ],
          ),
          if (m.reference != null || m.user != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (m.reference != null)
                  Text(
                    'Ref ${m.reference}',
                    style: AppTextStyles.mono(size: 11, color: AppColors.textMuted),
                  ),
                if (m.reference != null && m.user != null) const SizedBox(width: 12),
                if (m.user != null)
                  Expanded(
                    child: Text(
                      m.user!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(size: 11, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tablet / web layout: a real table with one column per field.
class _MovementTable extends StatelessWidget {
  final List<InventoryMovement> items;
  const _MovementTable({required this.items});

  static const _flex = [30, 38, 24, 14, 12, 22, 20, 24]; // date, item, variant, qty, unit, type, ref, user

  Widget _cell(int column, Widget child, {Alignment alignment = Alignment.centerLeft}) {
    return Expanded(
      flex: _flex[column],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(alignment: alignment, child: child),
      ),
    );
  }

  Widget _header() {
    TextStyle style() => AppTextStyles.mono(
          size: 10,
          weight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 1.5,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          _cell(0, Text('DATE', style: style())),
          _cell(1, Text('ITEM', style: style())),
          _cell(2, Text('VARIANT', style: style())),
          _cell(3, Text('QTY', style: style()), alignment: Alignment.centerRight),
          _cell(4, Text('UNIT', style: style())),
          _cell(5, Text('TYPE', style: style())),
          _cell(6, Text('REFERENCE', style: style())),
          _cell(7, Text('USER', style: style())),
        ],
      ),
    );
  }

  Widget _row(InventoryMovement m) {
    final color = _typeColor(m);
    final sign = m.isReceiving ? '+' : '-';
    final muted = AppTextStyles.body(size: 12, color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          _cell(0, Text(_formatDate(m.date), style: AppTextStyles.body(size: 12, color: AppColors.textSecondary))),
          _cell(
            1,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.itemName, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(size: 13, weight: FontWeight.w600)),
                Text(m.reason, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(size: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          _cell(2, Text(m.variantName ?? '—', overflow: TextOverflow.ellipsis, style: muted)),
          _cell(
            3,
            Text('$sign${_trimZeros(m.quantity)}', style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, color: color)),
            alignment: Alignment.centerRight,
          ),
          _cell(4, Text(m.unit.isEmpty ? '—' : m.unit, style: AppTextStyles.body(size: 12, color: AppColors.textSecondary))),
          _cell(5, _TypeChip(movement: m)),
          _cell(6, Text(m.reference ?? '—', overflow: TextOverflow.ellipsis, style: AppTextStyles.mono(size: 11.5, color: AppColors.textMuted))),
          _cell(7, Text(m.user ?? '—', overflow: TextOverflow.ellipsis, style: muted)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: Column(
        children: [
          _header(),
          Divider(height: 1, color: AppColors.slateBorder),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.slateBorder),
              itemBuilder: (_, index) => _row(items[index]),
            ),
          ),
        ],
      ),
    );
  }
}
