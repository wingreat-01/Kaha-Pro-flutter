import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../state/cart_provider.dart';
import '../state/product_provider.dart';
import '../state/recipe_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/category_sidebar.dart';
import '../widgets/category_segmented_tabs.dart';
import '../widgets/catalog_search_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/add_product_card.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/product_size_picker_sheet.dart';
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
  final String? cashierName;
  const RegisterScreen({super.key, this.cashierName});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String _selectedCategory = 'All';
  bool _editMode = false;
  String _searchQuery = '';

  static const double _wideBreakpoint = 700;
  static const double _sidebarWidth = 200;
  static const double _cartPanelWidth = 320;

  // Category tabs now come straight from ProductProvider.categories
  // (Supabase-backed, includes 'All' + every category row — even ones
  // with zero products, e.g. a freshly-added "Add Ons"). There used to
  // be a hardcoded _categoryTabs list here as a second source of
  // truth; that meant deleting a category in Settings never removed it
  // from this screen since it wasn't reading from the same data at
  // all. catalog.categories is reactive via notifyListeners, so
  // deletes/renames/adds in Settings now show up here immediately —
  // no hot restart needed.

  List<Product> _filtered(ProductProvider catalog) {
    // A live search query overrides whichever category tab happens to
    // be selected — search scans every category (including
    // Uncategorized, unlike "All"), so a cashier searching "Kimchi"
    // while sitting on the "Drinks" tab still finds it instead of
    // seeing zero results and assuming the product doesn't exist.
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      return catalog.products.where((p) => p.name.toLowerCase().contains(query)).toList();
    }

    // "All" excludes Uncategorized products — since there's no tab to
    // select Uncategorized directly anymore, a product that lands
    // there (e.g. its category was just deleted) is hidden from the
    // register grid entirely until someone re-tags it into a real
    // category in Settings. Prevents an orphaned product from still
    // being sold under a category that no longer exists.
    if (_selectedCategory == 'All') {
      return catalog.products.where((p) => p.category != ProductProvider.uncategorized).toList();
    }
    return catalog.products.where((p) => p.category == _selectedCategory).toList();
  }

  void _onCheckout(BuildContext context, CartProvider cart) {
    CheckoutModal.show(
      context,
      cart,
      cashierName: widget.cashierName,
      onComplete: (result) {
        final synced = result == CheckoutResult.completedSynced;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.slate,
            content: Text(
              synced ? 'Sale completed' : 'Sale saved offline — will sync when back online',
              style: AppTextStyles.body(size: 13, color: synced ? AppColors.tillGreen : AppColors.ledAmber),
            ),
          ),
        );
      },
    );
  }

  void _openAddProductDialog(BuildContext context, ProductProvider catalog) {
    // Captured here (not inside onSubmit) same reasoning as catalog
    // itself — this method already runs with a valid context, and the
    // onSubmit closure below fires later, after the dialog's Navigator
    // pop, when context.read would still work but there's no reason
    // to re-fetch it.
    final recipes = context.read<RecipeProvider>();
    // catalog.categoryNames is already the live, Supabase-backed list
    // (no 'All' in it), so the dialog's dropdown can use it directly —
    // no need to reconcile it against a separate hardcoded tab list.
    showDialog(
      context: context,
      builder: (_) => AddProductDialog(
        existingCategories: catalog.categoryNames,
        initialCategory: _selectedCategory,
        productLimit: catalog.productLimit,
        currentProductCount: catalog.productCount,
        // onUpgradeTap: left unwired until an upgrade screen/flow exists
        // (per the subscription plan doc's build order) — Cancel-only
        // for now on the limit-reached view.
        onSubmit: ({required name, required price, required category, emoji, imageBytes, trackStock = false, unit = 'pc', unitLabel, variants = const [], recipeItems = const []}) {
          catalog
              .addProduct(
                name: name,
                price: price,
                category: category,
                emoji: emoji,
                imageBytes: imageBytes,
                trackStock: trackStock,
                unit: unit,
                unitLabel: unitLabel,
              )
              .then((newId) async {
            // Sizes were staged locally in the dialog since the
            // product didn't have an id yet — attach them now that it
            // does. Fired one at a time (not Future.wait) so a single
            // failed size doesn't risk an interleaved partial write;
            // at this volume (a handful of sizes per product) the
            // sequential round trips are unnoticeable.
            //
            // Real ids are captured in save order so recipe rows
            // scoped to a specific size (see below) can be resolved
            // to the right one — ASSUMES ProductProvider.addVariant
            // returns the new variant's id; if it currently returns
            // void, that's a small follow-on change needed there. A
            // failed size gets an empty-string placeholder so the
            // index alignment with `variants` doesn't shift.
            final savedVariantIds = <String>[];
            for (final v in variants) {
              try {
                final variantId = await catalog.addVariant(newId, name: v.name, price: v.price);
                savedVariantIds.add(variantId);
              } catch (e) {
                savedVariantIds.add('');
                debugPrint('Could not add size "${v.name}" to new product $newId: $e');
              }
            }
            // Same staged-then-attach pattern for recipe rows — the
            // recipe editor couldn't write to product_recipe_items
            // without a product_id either, so its drafts land here too.
            // A row scoped to a specific size carries an "idx:n"
            // placeholder (see RecipeEditor.sizes doc) instead of a
            // real variant id, since the size didn't have one yet at
            // draft time — resolve it against savedVariantIds now.
            for (final r in recipeItems) {
              String? resolvedVariantId;
              final key = r.variantKey;
              if (key != null) {
                if (key.startsWith('idx:')) {
                  final idx = int.tryParse(key.substring(4));
                  final resolved = idx != null && idx >= 0 && idx < savedVariantIds.length
                      ? savedVariantIds[idx]
                      : '';
                  if (resolved.isEmpty) {
                    debugPrint('Skipping recipe item for new product $newId — its size failed to save');
                    continue;
                  }
                  resolvedVariantId = resolved;
                } else {
                  // Shouldn't normally happen for a new product (sizes
                  // never have real ids yet at draft time), but harmless
                  // to pass through rather than drop the row.
                  resolvedVariantId = key;
                }
              }
              try {
                await recipes.addItem(
                  productId: newId,
                  variantId: resolvedVariantId,
                  ingredientId: r.ingredientId,
                  quantityUsed: r.quantityUsed,
                );
              } catch (e) {
                debugPrint('Could not add recipe item to new product $newId: $e');
              }
            }
          }).catchError((e) {
            if (!context.mounted) return;
            // Rare path — the dialog's own limit check should catch
            // this before submit in almost every case; this only fires
            // if the plan/count went stale mid-dialog (e.g. another
            // device added the last slot) and the server trigger
            // rejected the insert.
            final message = e is ProductLimitExceededException
                ? e.message
                : 'Couldn\'t add product — try again';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.slate,
                content: Text(
                  message,
                  style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed),
                ),
              ),
            );
          });
        },
      ),
    );
  }

  void _openEditProductDialog(BuildContext context, ProductProvider catalog, Product product) {
    showDialog(
      context: context,
      builder: (_) => AddProductDialog(
        existingCategories: catalog.categoryNames
            .where((c) => c != ProductProvider.uncategorized)
            .toList(),
        editingProduct: product,
        onSubmit: ({required name, required price, required category, emoji, imageBytes, trackStock = false, unit = 'pc', unitLabel, variants = const [], recipeItems = const []}) async {
          try {
            await catalog.updateProduct(
              product.id,
              name: name,
              price: price,
              category: category,
              emoji: emoji,
              trackStock: trackStock,
              unit: unit,
              unitLabel: unitLabel,
            );
            if (imageBytes != null) {
              await catalog.updateProductImage(product.id, imageBytes);
            }
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.slate,
                content: Text(
                  "Couldn't save changes — try again",
                  style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed),
                ),
              ),
            );
          }
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

  void _onProductTap(BuildContext context, CartProvider cart, Product product) {
    if (_editMode) return; // edit mode taps go through onEdit, not onTap
    if (!product.hasVariants) {
      cart.add(product);
      return;
    }
    ProductSizePickerSheet.show(
      context,
      product: product,
      onSelected: (variant) => cart.add(product, variant: variant),
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

  void _onImageSelected(BuildContext context, ProductProvider catalog, Product product, Uint8List bytes) {
    catalog.updateProductImage(product.id, bytes).catchError((e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.slate,
          content: Text(
            'Photo upload failed — try again',
            style: AppTextStyles.body(size: 13, color: AppColors.ledgerRed),
          ),
        ),
      );
    });
  }

  Widget _buildGrid(BuildContext context, CartProvider cart, ProductProvider catalog, double gridWidth) {
    final crossAxisCount = gridWidth < 480
        ? 2
        : gridWidth < 800
            ? 3
            : gridWidth < 1050
                ? 4
                : gridWidth < 1300
                    ? 5
                    : gridWidth < 1600
                        ? 6
                        : 7;

    final products = _filtered(catalog);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CatalogSearchBar(
                // catalog.products is already the full in-memory list
                // (same one _filtered() reads) — no separate fetch,
                // this is a pure client-side name filter.
                suggestions: catalog.products.map((p) => p.name).toList(),
                onQueryChanged: (query) => setState(() => _searchQuery = query),
              ),
              const SizedBox(width: 4),
              _editToggle(context),
            ],
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
                onTap: () => _onProductTap(context, cart, product),
                onEdit: () => _openEditProductDialog(context, catalog, product),
                onDelete: () => _confirmDelete(context, catalog, product),
                onImageSelected: (bytes) => _onImageSelected(context, catalog, product, bytes),
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

    // Live, Supabase-backed category list — replaces the old hardcoded
    // _categoryTabs. If the currently-selected category no longer
    // exists (e.g. it was just deleted in Settings), fall back to
    // 'All' rather than showing an empty grid for a tab that's gone.
    // "Uncategorized" is a fallback bucket (where products land after
    // their category is deleted) rather than something a cashier ever
    // chooses on purpose — hidden from the register nav so it doesn't
    // clutter the tab list, but products in it are still fully
    // sellable via "All". Settings still shows it as its own
    // uneditable/undeletable category so it stays visible for cleanup.
    final categoryTabs = catalog.categories
        .where((c) => c != ProductProvider.uncategorized)
        .toList();
    if (!categoryTabs.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;

        if (isWide) {
          final contentWidth = constraints.maxWidth - _sidebarWidth - _cartPanelWidth;
          return Row(
            children: [
              CategorySidebar(
                categories: categoryTabs,
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
              categories: categoryTabs,
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
