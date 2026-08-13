# KahaPro — Inventory / Raw Materials System

## Where this fits

KahaPro's current inventory (Phase 3) tracks stock **per product**: sell
one Iced Latte, deduct one Iced Latte from stock. That works for
products bought/resold as-is (bottled drinks, hardware, packaged
snacks), but breaks down for anything **made to order** — a barista
assembling an Iced Latte doesn't have "Iced Latte" units sitting in a
fridge; they have cups, milk, coffee beans, syrup.

This doc covers the next layer: a **separate raw-materials/supplies
system**, connected to sellable Products only through optional
recipes, designed to work the same way whether the owner is a
hardware store, a mini grocery, or a café.

---

## Step 0 — The business-type picker

Different owners think about their stock in different vocabulary — a
café calls it "Ingredients," a hardware store or mini grocery would
find that term confusing. Rather than pick one universal term (or
build a whole configurable-labels settings screen), a single
**business type** field set once at store setup drives both the UI
label and sensible defaults:

```
Store
  ...existing fields...
  business_type   'food_beverage' | 'retail_hardware' | 'general'
```

| business_type | Inventory screen label | New-product default |
|---|---|---|
| `food_beverage` | "Ingredients" | suggests recipe mode when adding a product |
| `retail_hardware` | "Supplies" (or "Raw Materials") | suggests flat-unit stock (`pc`, `sack`, `kg`) |
| `general` / unset | "Raw Materials" (safe default) | no suggestion either way |

This is a one-line label swap sourced from `store.business_type` — a
single string constant read wherever the Inventory screen title,
empty-state copy, and "+ Add ___" button currently render — not a
schema or logic fork. Nothing about the underlying data model or
recipe mechanics changes based on this field; it only changes what
the owner reads on screen. A café can still stock hardware-style flat
items (bottled water) and a hardware store can still build a recipe
(e.g. a "custom paint mix" product) if they want to — the picker sets
the default expectation, it never locks a store out of the other mode.

Asked once during store setup (or editable later from Settings →
Store details), alongside whatever other store-profile fields already
exist there.

---

## Step 1 — Units of measure

Every stocked item — product or raw material — needs a unit so its
stock quantity actually means something:

| Unit | Label | Typical use |
|---|---|---|
| `pc` | piece(s) | cups, lids, straws, hardware items, packaged goods |
| `g` | grams | coffee beans, powders, spices |
| `kg` | kilograms | bulk dry goods (flour, sugar, rice, cement by weight) |
| `ml` | milliliters | milk, syrups, sauces, paint |
| `L` | liters | bulk liquids bought in bottles/jugs |
| `pack` / `box` | pack(s) | bulk packs consumed individually (napkins, screws, sachets) |
| `sack` | sack(s) | cement, rice, feeds |
| `custom` | (free text) | anything else — "roll," "bundle," "meter" |

Each item stores its stock in **one base unit** (e.g. always grams for
coffee beans, never a mix of g and kg) to keep the math simple — the
UI can still *display* kg for a large quantity while storing grams
underneath, same idea as currency always being stored in centavos.

**`Product` gets its own `unit` field**, defaulting to `pc` — this is
what lets a hardware store sell "Cement" by the sack instead of
assuming pieces, with zero migration pain for existing rows (they all
default to `pc`, behaving exactly as today).

---

## Step 2 — The question to ask the owner

> **"When you sell one product, do you want the system to automatically
> deduct the supplies used to make that product?"**

This is the fork in the road:

- **No** → they just want simple per-product stock (`Product.unit` +
  `stock_quantity`, Step 1 above — already covers hardware/grocery).
  Nothing more to build.
- **Yes** → they're describing a **recipe / Bill of Materials (BOM)**
  system: each sellable product is defined not just by its price, but
  by a *list of raw materials and quantities* it consumes. Worth
  treating as one of KahaPro's flagship features — most small
  cafés/food stalls track this on paper or not at all.

### Example: Iced Latte × 1 sold

| Raw material | Deducted |
|---|---|
| 12oz Cup | 1 pc |
| Lid | 1 pc |
| Straw | 1 pc |
| Coffee Beans | 18 g |
| Whole Milk | 200 ml |

---

## Step 3 — If yes: the recipe system design

### A genuinely separate system, not a Products mode

Raw materials live in their **own table**, managed from their **own
admin screen** — not folded into `Product` via a flag, and never
touching the Register grid query at all (not filtered out — simply
never in that table to begin with):

```
Ingredient
  id
  store_id            (multi-tenant scope, same as products/categories)
  name                e.g. "Coffee Beans", "Whole Milk", "12oz Cup"
  unit                pc | g | kg | ml | L | pack | sack | custom
  stock_quantity      numeric — current amount on hand, in the unit above
  low_stock_threshold  optional — for a restock alert
  cost_per_unit       optional — enables ingredient-level COGS later
```

(`Ingredient` stays the internal/code-level name regardless of what
the UI calls it per Step 0 — the model doesn't need to change just
because the label does.)

### The bridge — recipes

```
ProductRecipeItem
  id
  product_id        → Product.id  (a normal sellable product)
  variant_id         → optional, ProductVariant.id — a "Large" Iced
                        Latte can use more milk than a "Medium" one;
                        null means this line applies regardless of size
  ingredient_id      → Ingredient.id
  quantity_used      numeric, in the ingredient's own unit
                        (18 for grams, 200 for ml, 1 for pc)
```

A product with no `ProductRecipeItem` rows behaves exactly like today
— flat `Product.unit`/`stock_quantity` deduction, or no deduction at
all if it isn't tracked. A product with recipe rows switches to
raw-material deduction instead.

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

- **Product add/edit dialog**: add a Unit dropdown next to the
  existing stock quantity field (defaults to `pc`, matching today's
  behavior). Doesn't touch the raw-materials side at all.
- **Inventory panel** (its own admin screen, same tier as
  Products/Categories/Settings — not a filtered view of Products;
  screen title and empty-state copy pulled from Step 0's business-type
  label): list, add/edit/delete raw materials, set unit + starting
  stock + low-stock threshold. This is where raw materials actually
  get created and managed.
- **Recipe editor**, embedded in the product add/edit dialog similar
  to how `ProductVariantEditor` works today: "This product uses
  [ingredients/supplies]" toggle → rows of (item picker — pulled from
  the Inventory panel's existing list, quantity, unit shown read-only).
  This only *references* items; it doesn't create new ones (a
  quick-add shortcut here is a nice-to-have later, but the Inventory
  panel stays the source of truth).
- **Low-stock view**: raw materials below their threshold, surfaced
  the same way a low-stock product would be today.

### Reporting hooks

Once this exists, [[sales-reports]]-style questions extend naturally:
- "What am I running low on?"
- "How much coffee beans did I use this week?"
- "What's my ingredient cost vs. revenue?" (needs `cost_per_unit` filled in)

---

## Open questions to resolve before building

- Does stock get **restocked manually** (owner enters "received 5kg
  coffee beans") or does KahaPro need a purchasing/PO flow too?
  (Manual restock is the sane MVP.)
- Should recipe deduction be **all-or-nothing** per sale, or can a
  cashier override/skip it for a specific sale (e.g. a customer asks
  for no lid)?
- Negative-stock policy: block the sale, warn but allow, or silently
  allow? (Recommend: warn but allow — matches how most small
  business owners actually operate.)
- Multi-tenant scope: `Ingredient` should be `store_id`-scoped like
  everything else in the Phase B schema, so one client's raw-materials
  list never leaks into another's.
- Is `business_type` set once at store creation and editable later
  from Settings, or locked after signup? (Recommend: editable later —
  an owner might mis-pick during onboarding, or a business might
  genuinely span both, e.g. a grocery that also runs a small deli
  counter.)

## Suggested build order

1. `Product.unit` column (backward-compatible, default `'pc'`) —
   unlocks hardware/grocery flat-unit stock immediately, no other
   dependency
2. `Store.business_type` field + the setup-flow picker
3. `Ingredient` table + standalone Inventory admin screen (label
   driven by `business_type`)
4. `ProductRecipeItem` + the recipe editor inside the product dialog
5. Checkout-time deduction logic + negative-stock policy
6. Low-stock view + reporting hooks
