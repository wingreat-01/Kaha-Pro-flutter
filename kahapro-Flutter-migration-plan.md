# Kahapro → Flutter migration — project plan (updated)

## Project
Kahapro is a POS (point of sale) web app, originally a single `index.html`
file (login gate, register/cart, inventory, admin panels, theming). Goal:
rebuild it natively in Flutter so it runs as **one codebase for both a
phone app (Android/iOS) and a web app**.

"Kaha" is Tagalog for cash box/register — the visual identity leans into
that directly (see Design system below).

## Decisions made so far
- **Not** a mechanical HTML→Flutter conversion — every screen is hand-built
  in Dart. App **logic** carried over faithfully; **visual design** rebuilt
  from scratch.
- Target: both mobile and web from one Flutter codebase.
- Workflow: no VS Code — user uploads files / works via chat with Claude,
  who edits and hands back files to drop into the Flutter project locally.
- State management: `provider` package (`ChangeNotifier`), via `MultiProvider`
  wrapping the app in `main.dart`.
- Flutter SDK installed on Windows at `Desktop\flutter`; project at
  `Desktop\Desktop\kahapro_flutter` (note: nested `Desktop` folder per
  terminal paths seen so far).

## Design system (built, in use)
Signature idea: the app looks and feels like an actual cash register /
calculator.

**Palette** — Charcoal `#1E2126` (base), Slate `#2A2E35` (surfaces),
LED Amber `#FFB020` (primary accent), Till Green `#3FA796` (confirm),
Ledger Red `#E4572E` (errors/voids), Paper cream `#F6F1E4` (receipts only).

**Type** — IBM Plex Mono (numeric/display), Manrope (body/UI).

**Signature element** — glowing amber monospace total readout
(`LedTotal` widget), used in the cart panel, the Pass C checkout
modal (TOTAL DUE / CHANGE), and the transaction detail view
(TOTAL / TENDERED / CHANGE).

## Migration phases — status

- [x] **Phase 1 — foundation (superseded)**: project scaffold, theme
      system, login screen — old look, rebuilt in 1.5.
- [x] **Phase 1.5 — new design system**: charcoal/amber/mono theme and
      login screen. Confirmed working.
- [~] **Phase 2 — Register screen**: in progress, built in passes:
  - [x] **Pass A** — category tabs + responsive product grid (2–5
        columns by width), static mock data. Confirmed working after
        home shell was correctly wired.
  - [x] **Pass B** — cart wired via `CartProvider`, amber LED total,
        qty +/- steppers, wide side panel vs. phone collapsed bottom
        bar (expands to a drag-up sheet). Confirmed reaching the home
        shell with cart bar visible; full interaction not yet
        separately confirmed.
  - [x] **Category navigation redesign** — replaced the horizontal
        chip row with: left sidebar nav (icons + labels) on wide/web,
        segmented underlined top tabs on phone. (Old `category_tabs.dart`
        chip widget is now unused — safe to delete.)
  - [x] **Customizable catalog** — `ProductProvider` (`ChangeNotifier`)
        holds a mutable in-memory product list. "+" add-product tile
        opens a dialog (name, price, category, optional emoji, new-category
        support). "Edit / Done" toggle above the grid shows a delete X
        badge on each card when active, with a confirm dialog before
        removal. **Code delivered but STILL not confirmed working
        end-to-end** — last report was the Edit toggle not appearing,
        most likely because the updated files weren't fully saved
        before restart (recurring issue — see note below). Deliberately
        deferred again this session in favor of closing out Pass C
        first (decision: finish Pass C, then Phase 3 — see below).
  - [x] **Card sizing/uniformity pass** — product grid cards made
        consistent size.
  - [x] **Phone tab bar rework** — maximized to show 4 tabs, added
        scroll/swipe, added desktop mouse-drag support for the same
        tab bar.
  - [x] **Fixed placeholder tab list** — replaced earlier ad-hoc tab
        source with a fixed list.
  - [x] **Cart line-item removal** — added `_RemoveButton` (✕) at the
        end of each cart row in `cart_list.dart`, wired to
        `cart.remove(item.product.id)`; deletes the line entirely
        (distinct from the −/+ qty stepper). Shared by `CartList`, so
        it works in both the wide side panel and the phone bottom
        sheet automatically.
  - [x] **`ListenableBuilder` fix** — phone bottom sheet now reflects
        cart changes (incl. the new remove button) live instead of
        going stale.
  - [x] Checkout modal (**Pass C**) — payment entry, change calculation,
        `LedTotal` reused prominently (TOTAL DUE amber, CHANGE in Till
        Green). Built as `checkout_modal.dart`, opened via
        `CheckoutModal.show(context, cart, onComplete)` from
        `_onCheckout` in `register_screen.dart` — that call site and
        the `onCheckout` wiring in `cart_side_panel.dart` /
        `cart_bottom_bar.dart` were already in place, just waiting on
        the modal file. Confirm button validates tendered ≥ total
        (inline red error if short), then logs a transaction (see
        Transactions below) and clears the cart.
        **Quick-amount chip rule**:
        - At/under ₱1000 (largest common peso bill): chips are actual
          bill values (₱50/₱100/₱500/₱1000), filtered to only those
          that alone cover the total, labeled `+₱__`, and *additive*
          (tapping stacks bills onto whatever's already entered).
        - Above ₱1000: no single bill covers it, so chips switch to
          computed round-up targets — next ₱50, next ₱100, next ₱500
          above the total, de-duplicated — labeled `₱__` (no `+`) and
          tapping *sets* the field directly rather than adding.
          Confirmed pattern (e.g. ₱1043 → ₱1050/₱1100/₱1500; ₱1083 →
          ₱1100/₱1500; ₱1540 → ₱1550/₱1600/₱2000).
- [x] **Phase 3 — Transactions & Inventory panels**: complete.
  - [x] **Transaction logging + Transactions tab** — `Transaction` /
        `TransactionLineItem` models (`lib/models/transaction.dart`)
        snapshot each cart line at sale time (name/price/qty/category
        copied out, not referenced, so later catalog edits/deletes
        never retroactively change a past sale's record).
        `TransactionProvider` (`ChangeNotifier`, registered in
        `main.dart`'s `MultiProvider`) logs one entry per confirmed
        checkout with a ledger-style number (`#00001`, `#00002`, …),
        timestamp, line items, total, cash tendered, and change.
        `checkout_modal.dart`'s confirm step records the transaction
        before clearing the cart. The **Transactions tab** in
        `register_screen.dart` now swaps in `transactions_panel.dart`
        (list, newest first, no add-product tile / no Edit toggle —
        those only apply to the catalog grid) instead of the product
        grid; tapping a row opens `transaction_detail_modal.dart`
        with the full line-item breakdown and totals.
  - [x] **Day summary / history rollups** — `TransactionProvider`'s
        `dailySummaries` getter groups logged transactions by calendar
        day (newest day first), backing the Transactions tab's daily
        totals. Confirmed done.
  - [x] **Real inventory list/add/edit panel** — `InventoryPanel`
        (`lib/screens/inventory_panel.dart`), reached via **Settings →
        Products**. Stock lives directly on `Product`
        (`stockQty`, `lowStockThreshold`, `isLowStock` getter) rather
        than a separate parallel list, so it can't drift out of sync
        with the catalog. `ProductProvider` gained `adjustStock`
        (± delta, clamped at 0), `setStock` (absolute, for recounts),
        `setLowStockThreshold`, and `lowStockProducts`. Rows show a
        red "LOW" badge at/below threshold, +/- steppers, and a tap
        opens a dialog to set exact stock + edit the threshold.
        **Checkout now deducts stock automatically**: `ProductProvider
        .deductStockForSale(List<CartItem>)` is called from
        `checkout_modal.dart`'s `_confirm()` right after the sale is
        recorded and before the cart clears, using the same pre-clear
        cart snapshot the transaction was logged from.
- [x] **Header navigation restructure**: Transactions, Users, and
      Settings used to be crammed into the register screen's category
      tab row alongside real product categories — overflowed the tab
      bar on phone widths and mixed "what am I selling" with "where do
      I manage the app." Now: `HomeShell` (`lib/screens/home_shell.dart`)
      owns top-level section state and shows four header icons —
      **Register** (point-of-sale icon) → **Transactions** (receipt
      icon) → **Settings** (gear icon) → **Logout** — with the active
      section's icon lit amber. `register_screen.dart`'s category tabs
      now hold only real product categories (`All`, `Main`, `Add Ons`,
      `Drinks`). New `SettingsPanel` (`lib/screens/settings_panel.dart`)
      houses **Users** (moved here from being its own top-level tab),
      **Categories**, **Products** (opens `InventoryPanel`), **Store
      details**, and **About** — all but Products are still Phase 4
      placeholders.
- [x] **Checkout modal first-open jank fix**: new `CheckoutWarmup`
      widget (`lib/widgets/checkout_warmup.dart`), mounted in
      `HomeShell`. Invisibly pre-renders the same `LedTotal`
      mono-font readouts and rounded-container styling the checkout
      modal uses, for exactly one frame right after login, so the
      IBM Plex Mono glyph rasterization/shader-compile cost is paid
      quietly instead of during a cashier's first real checkout. Then
      unmounts itself.
- [ ] **Phase 4 — Admin**: Users, Products, Categories managers. Not
      started.
- [ ] **Phase 5 — Polish**: animations (digit flip on total change),
      further responsive tuning, real app icon, real authentication
      (current login accepts any non-empty username/password — this is
      intentional as a placeholder, not a bug). Not started.

## Known recurring gotcha
Several rounds this session where a file was re-sent by Claude but the
**previous** version was still what ran, because the local save didn't
fully take before a hot reload/restart. Hot restart (`R`) does not
reliably re-run `main()` on the web-server target in particular. When
something looks unchanged after pasting a file: (1) confirm the file
actually contains the new content (search for a known new string/line),
(2) fully quit (`q`) rather than hot-restart, (3) run `flutter run -d chrome`
fresh. `flutter run -d chrome` has also failed to launch the browser at
least once this session, silently falling back to `-d web-server`
(different port each time) — worth watching for in terminal output.

## Project structure (current, local)
```
Desktop/
  flutter/                        ← Flutter SDK
  Desktop/kahapro_flutter/        ← app project
    lib/
      main.dart                   ← MultiProvider(CartProvider, ProductProvider, TransactionProvider)
      theme/app_theme.dart
      state/
        cart_provider.dart
        product_provider.dart
        transaction_provider.dart ← logs completed sales, ledger-style numbering
      models/
        product.dart               ← now includes stockQty, lowStockThreshold, isLowStock
        cart_item.dart
        transaction.dart          ← Transaction + TransactionLineItem (immutable snapshot)
      data/
        mock_products.dart        ← seed data for ProductProvider
      screens/
        login_screen.dart
        home_shell.dart           ← owns top-level section nav (Register/Transactions/Settings) + header icons
        register_screen.dart      ← category tabs now hold only real product categories
        settings_panel.dart       ← Users/Categories/Products(→Inventory)/Store details/About
        inventory_panel.dart      ← stock list, low-stock badges, +/- steppers, restock/threshold dialog
      widgets/
        category_sidebar.dart         (wide/web)
        category_segmented_tabs.dart  (phone)
        category_tabs.dart            (superseded, unused — safe to delete)
        product_card.dart             (tap-to-add + edit-mode delete X)
        add_product_card.dart         (dashed "+" tile)
        add_product_dialog.dart       (add-product form)
        cart_side_panel.dart          (wide/web)
        cart_bottom_bar.dart          (phone, expands to sheet)
        cart_list.dart                (shared qty-stepper list, incl. ✕ remove)
        led_total.dart                (glowing amber total readout)
        checkout_modal.dart           (Pass C: cash entry, quick chips, change calc, deducts stock on confirm)
        checkout_warmup.dart          (pre-warms checkout modal's font/paint cost once after login)
        transactions_panel.dart       (Transactions tab list, incl. day summaries)
        transaction_detail_modal.dart (tap a transaction row for detail)
    assets/logo.png
    pubspec.yaml                  ← needs: provider, google_fonts
```

## Also deployed (separate, non-Flutter track)
The original HTML `index.html` was set up as a ready-to-go Firebase
Hosting project, independent of the Flutter migration.

## Planned — Supabase integration (auth, database, storage)
Not started. Everything currently in the Flutter app is in-memory only
(`ProductProvider`, `CartProvider`, `TransactionProvider` all lose state
on restart) — Supabase is intended to replace that with real persistence:
- **Authentication** — replace the current placeholder login (accepts
  any non-empty username/password) with real Supabase Auth. Ties into
  Phase 5's "real authentication" item and Phase 4's Users admin panel.
- **Database** — persist products/catalog, cart/transactions, and users
  in Supabase (Postgres) instead of the in-memory providers. This is
  the natural backing store for Phase 3's inventory panel and
  transaction history, and Phase 4's admin managers.
- **Storage** — Supabase Storage for product images/assets (currently
  just an optional emoji per product) and possibly receipt/export
  files down the line.

No decisions yet on schema, RLS policies, or how far to go before
wiring each provider to Supabase vs. keeping them in-memory for now —
to be worked out when this track starts.

## How to resume
Tell Claude: "continue the Kahapro Flutter migration — start the
Supabase integration (auth, database, storage)." Phase 3 (Transactions,
day summaries, and the real inventory panel) is done; the remaining
open work is Phase 4 (Admin: Users, Products, Categories managers —
`SettingsPanel`'s rows are already placeholders waiting on these) and
Phase 5 (Polish: animations, further responsive tuning, real app icon,
real authentication). Upload this file at the start of a fresh
conversation so context carries over.
