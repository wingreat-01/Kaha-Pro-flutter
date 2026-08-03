import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/cart_provider.dart';
import '../state/product_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/category_sidebar.dart';
import '../widgets/category_segmented_tabs.dart';
import '../widgets/product_card.dart';
import '../widgets/add_product_card.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/cart_side_panel.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/checkout_modal.dart';

/// Phase 2 — Pass B + C: cart wired via CartProvider, amber LED total,
/// dashboard-style category navigation, a customizable catalog (add
/// products via a dialog, delete via an edit-mode toggle), and a
/// checkout modal (cash tendered, live change calc, complete sale).
///
/// Transactions / Users / Settings are no longer part of this screen's
/// tabs — they moved up to HomeShell (Transactions + Settings as header
/// icons, Users nested inside Settings). This screen now only ever
/// shows the product grid, filtered by real category.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String _selectedCategory = 'All';
  bool _editMode = false;

  static const double _wideBreakpoint = 700;
  static const double _sidebarWidth = 200;
  static const double _cartPanelWidth = 320;

  // Real product-category tabs only. Transactions/Users/Settings used to
  // live here too, which both overflowed the phone tab bar and mixed nav
  // concerns with category filtering — they're header icons now.
  static const List<String> _categoryTabs = [
    'All',
    'Main',
    'Add Ons',
    'Drinks',
  ];

  // "All" is the only tab that isn't a real product category.
  static const Set<String> _nonCategoryTabs = {'All'};

  // The set of "known" category names: tabs we show nav-wise as categories,
  // whether or not any product currently has that category yet (e.g. a
  // freshly-added tab like "Add Ons" with zero products still counts).
  List<String> _knownCategories(ProductProvider catalog) {
    final fromProducts = catalog.categories.where((c) => c != 'All');
    final fromTabs = _categoryTabs.where((t) => !_nonCategoryTabs.contains(t));
    return {...fromProducts, ...fromTabs}.toList()..sort();
  }

  List<Product> _filtered(ProductProvider catalog) {
    if (_selectedCategory == 'All') return catalog.products;
    return catalog.products.where((p) => p.category == _selectedCategory).toList();
  }

  void _onCheckout(BuildContext context, CartProvider cart) {
    CheckoutModal.show(context, cart, () {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.slate,
          content: Text(
            'Sale completed',
            style: AppTextStyles.body(size: 13, color: AppColors.tillGreen),
          ),
        ),
      );
    });
  }

  void _openAddProductDialog(BuildContext context, ProductProvider catalog) {
    final existing = _knownCategories(catalog);
    showDialog(
      context: context,
      builder: (_) => AddProductDialog(
        existingCategories: existing,
        initialCategory: _selectedCategory,
        onSubmit: ({required name, required price, required category, emoji, imageBytes}) {
          catalog.addProduct(name: name, price: price, category: category, emoji: emoji, imageBytes: imageBytes);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, ProductProvider catalog, Product product) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete product?', style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
        content: Text(
          'Remove "${product.name}" from the catalog? This can\'t be undone.',
          style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              catalog.removeProduct(product.id);
              Navigator.of(context).pop();
            },
            child: Text('Delete', style: AppTextStyles.body(size: 13, weight: FontWeight.w700, color: AppColors.ledgerRed)),
          ),
        ],
      ),
    );
  }

  Widget _editToggle(BuildContext context) {
    return TextButton.icon(
      onPressed: () => setState(() => _editMode = !_editMode),
      icon: Icon(
        _editMode ? Icons.check : Icons.edit_outlined,
        size: 16,
        color: _editMode ? AppColors.tillGreen : AppColors.textSecondary,
      ),
      label: Text(
        _editMode ? 'Done' : 'Edit',
        style: AppTextStyles.body(
          size: 12.5,
          weight: FontWeight.w600,
          color: _editMode ? AppColors.tillGreen : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, CartProvider cart, ProductProvider catalog, double gridWidth) {
    final crossAxisCount = gridWidth < 480
        ? 2
        : gridWidth < 900
            ? 3
            : gridWidth < 1300
                ? 4
                : 5;

    final products = _filtered(catalog);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [_editToggle(context)],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: products.length + 1, // +1 for the add-product tile
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              if (index == products.length) {
                return AddProductCard(onTap: () => _openAddProductDialog(context, catalog));
              }
              final product = products[index];
              return ProductCard(
                product: product,
                isEditMode: _editMode,
                onTap: () => cart.add(product),
                onDelete: () => _confirmDelete(context, catalog, product),
                onImageSelected: (bytes) => catalog.updateProductImage(product.id, bytes),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final catalog = context.watch<ProductProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;

        if (isWide) {
          final contentWidth = constraints.maxWidth - _sidebarWidth - _cartPanelWidth;
          return Row(
            children: [
              CategorySidebar(
                categories: _categoryTabs,
                selected: _selectedCategory,
                onSelected: (category) => setState(() => _selectedCategory = category),
              ),
              Expanded(child: _buildGrid(context, cart, catalog, contentWidth)),
              CartSidePanel(cart: cart, onCheckout: () => _onCheckout(context, cart)),
            ],
          );
        }

        return Column(
          children: [
            CategorySegmentedTabs(
              categories: _categoryTabs,
              selected: _selectedCategory,
              onSelected: (category) => setState(() => _selectedCategory = category),
            ),
            Expanded(child: _buildGrid(context, cart, catalog, constraints.maxWidth)),
            CartBottomBar(cart: cart, onCheckout: () => _onCheckout(context, cart)),
          ],
        );
      },
    );
  }
}
