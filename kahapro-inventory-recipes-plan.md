# KahaPro — Ingredient/Supplies Inventory System

## Where this fits

KahaPro's current inventory (Phase 3) tracks stock **per product**: sell
one Iced Latte, deduct one Iced Latte from stock. That works for
products bought/resold as-is (bottled drinks, packaged snacks), but
breaks down for anything **made to order** — a barista assembling an
Iced Latte doesn't have "Iced Latte" units sitting in a fridge; they
have cups, milk, coffee beans, syrup.

This doc covers the next layer: tracking the raw **supplies/ingredients**
a product is made from, and (optionally) auto-deducting them from stock
every time that product sells.

---

## Step 1 — Units of measure

Every ingredient needs a unit so its stock quantity actually means
something. Support at least:

| Unit | Label | Typical use |
|---|---|---|
| `pc` | piece(s) | cups, lids, straws, packaging, single-use items |
| `g` | grams | coffee beans, powders, spices |
| `kg` | kilograms | bulk dry goods (flour, sugar, rice) |
| `ml` | milliliters | milk, syrups, sauces |
| `L` | liters | bulk liquids bought in bottles/jugs |
| `pack` / `box` | pack(s) | items bought in bulk packs but consumed individually (napkins, sachets) |

Each ingredient stores its stock in **one base unit** (e.g. always grams
for coffee beans, never a mix of g and kg) to keep the math simple —
the UI can still *display* kg for a large quantity while storing grams
underneath, same idea as currency always being stored in centavos.

**Ingredient record shape:**

```
Ingredient
  id
  store_id          (multi-tenant scope, same as products/categories)
  name              e.g. "Coffee Beans", "Whole Milk", "12oz Cup"
  unit              pc | g | kg | ml | L | pack
  stock_quantity    numeric — current amount on hand, in the unit above
  low_stock_threshold  numeric, optional — for a restock alert
  cost_per_unit     numeric, optional — enables ingredient-level COGS later
```

---

## Step 2 — The question to ask the owner

> **"When you sell one product, do you want the system to automatically
> deduct the supplies used to make that product?"**

This is the fork in the road:

- **No** → they just want simple per-product stock (what KahaPro
  already has). Nothing more to build.
- **Yes** → they're describing a **recipe / Bill of Materials (BOM)**
  system: each sellable product is defined not just by its price, but
  by a *list of ingredients and quantities* it consumes. This is
  worth treating as one of KahaPro's flagship features — most small
  cafés/food stalls track this on paper or not at all, and getting it
  automatic is a real differentiator.

### Example: Iced Latte × 1 sold

| Ingredient | Deducted |
|---|---|
| 12oz Cup | 1 pc |
| Lid | 1 pc |
| Straw | 1 pc |
| Coffee Beans | 18 g |
| Whole Milk | 200 ml |

---

## Step 3 — If yes: the recipe system design

### Data model

```
ProductRecipeItem
  id
  product_id        → Products.id  (which product this recipe line belongs to)
  variant_id         → optional, ProductVariant.id — a "Large" Iced Latte
                        can use more milk than a "Medium" one; null means
                        this line applies regardless of size
  ingredient_id      → Ingredient.id
  quantity_used      numeric, in the ingredient's own unit
                        (18 for grams, 200 for ml, 1 for pc)
```

A product with no `ProductRecipeItem` rows behaves exactly like today
— flat stock deduction, or no deduction at all if it isn't tracked.
A product with recipe rows switches to ingredient deduction instead.

### Checkout-time deduction

On `record_transaction` (or the client-side `deductStockForLineItems`
step already used for per-product stock), for each line item sold:

1. Look up that product's (and variant's, if any) recipe items
2. For each recipe item, subtract `quantity_used × line_item.quantity`
   from that ingredient's `stock_quantity`
3. If an ingredient's resulting stock would go negative, decide the
   policy up front — most POS systems let the sale go through anyway
   and just flag the ingredient as over-drawn/negative stock, rather
   than blocking a sale over a stock-counting gap

### Admin UI

- **Ingredients panel** (parallel to today's Products/Categories
  managers): list, add/edit/delete ingredients, set unit + starting
  stock + low-stock threshold
- **Recipe editor**, embedded in the product add/edit dialog similar
  to how `ProductVariantEditor` works today: "This product uses
  ingredients" toggle → rows of (ingredient picker, quantity, unit
  shown read-only from the ingredient)
- **Low-stock view**: ingredients below their threshold, surfaced the
  same way a low-stock product would be today

### Reporting hooks

Once this exists, [[sales-reports]]-style questions extend naturally:
- "What ingredients am I running low on?"
- "How much coffee beans did I use this week?"
- "What's my ingredient cost vs. revenue?" (needs `cost_per_unit` filled in)

---

## Open questions to resolve before building

- Does an ingredient's stock get **restocked manually** (owner enters
  "received 5kg coffee beans") or does KahaPro need a purchasing/PO
  flow too? (Manual restock is the sane MVP.)
- Should recipe deduction be **all-or-nothing** per sale, or can a
  cashier override/skip it for a specific sale (e.g. a customer asks
  for no lid)?
- Negative-stock policy: block the sale, warn but allow, or silently
  allow? (Recommend: warn but allow — matches how most small
  food-service owners actually operate.)
- Multi-tenant scope: ingredients should be `store_id`-scoped like
  everything else in the Phase B schema, so one client's ingredient
  list never leaks into another's.
