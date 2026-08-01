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

/// Phase 2 — Pass B: cart wired via CartProvider, amber LED total,
/// dashboard-style category navigation, and a customizable catalog
/// (add products via a dialog, delete via an edit-mode toggle).
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

  List<Product> _filtered(ProductProvider catalog) {
    if (_selectedCategory == 'All') return catalog.products;
    return catalog.products.where((p) => p.category == _selectedCategory).toList();
  }

  void _onCheckout(BuildContext context) {
    // Checkout modal is Pass C — placeholder confirmation for now.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.slate,
        content: Text(
          'Checkout modal coming in Pass C',
          style: AppTextStyles.body(size: 13, color: AppColors.ledAmber),
        ),
      ),
    );
  }

  void _openAddProductDialog(BuildContext context, ProductProvider catalog) {
    final existing = catalog.categories.where((c) => c != 'All').toList();
    showDialog(
      context: context,
      builder: (_) => AddProductDialog(
        existingCategories: existing,
        initialCategory: _selectedCategory,
        onSubmit: ({required name, required price, required category, emoji}) {
          catalog.addProduct(name: name, price: price, category: category, emoji: emoji);
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
              childAspectRatio: 0.86,
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
          final gridWidth = constraints.maxWidth - _sidebarWidth - _cartPanelWidth;
          return Row(
            children: [
              CategorySidebar(
                categories: catalog.categories,
                selected: _selectedCategory,
                onSelected: (category) => setState(() => _selectedCategory = category),
              ),
              Expanded(child: _buildGrid(context, cart, catalog, gridWidth)),
              CartSidePanel(cart: cart, onCheckout: () => _onCheckout(context)),
            ],
          );
        }

        return Column(
          children: [
            CategorySegmentedTabs(
              categories: catalog.categories,
              selected: _selectedCategory,
              onSelected: (category) => setState(() => _selectedCategory = category),
            ),
            Expanded(child: _buildGrid(context, cart, catalog, constraints.maxWidth)),
            CartBottomBar(cart: cart, onCheckout: () => _onCheckout(context)),
          ],
        );
      },
    );
  }
}
