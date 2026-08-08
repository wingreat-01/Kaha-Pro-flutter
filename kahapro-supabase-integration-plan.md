# Kahapro → Supabase Integration — status

## Goal
Replace the four in-memory `ChangeNotifier` providers (`ProductProvider`,
`CartProvider`, `TransactionProvider`, `UserProvider`) with real
persistence on Supabase (Postgres + Auth + Storage), and add an AI admin
assistant using the same provider-fallback pattern already proven in
UpaPro's "Agent Ria" (Gemini → Groq → Mistral), rehosted as a Supabase
Edge Function instead of a Firebase Cloud Function.

This tracks actual progress against the original sketch plan. Checked
items are confirmed built and working; unchecked items are still open.

## Open decisions — resolved or still open

- **Auth model (Phase C) — RESOLVED.** Went with **Option 2: shared
  owner session + PIN-gated `staff_users` table.** The store owner
  holds the one real Supabase Auth session (email+password via
  `signUp()`/`signInWithPassword()`); staff sign in with name+PIN,
  checked server-side against `staff_users` via `verify_staff_login()`.
  Keeps the original name+PIN UX intact.
- **Schema** — uuid PKs throughout (not the old `p_...`/`u_...` string
  ids). Tables confirmed to exist: `stores`, `store_members`,
  `store_counters`, `categories`, `products`, `staff_users`,
  `transactions`, `transaction_line_items`.
- **RLS policies** — `categories`, `products`, and `staff_users` each
  have a single "store scoped access" policy covering `ALL` commands
  (select/insert/update/delete), scoped to the signed-in owner's store.
  `transactions` and `transaction_line_items` are confirmed working
  end-to-end (see Phase F below) — RLS on both is scoped correctly for
  a real authenticated session; exact policy shape not separately
  re-verified since it works in practice.
  `store_counters` **RESOLVED** — confirmed via `pg_policies` to already
  have a "store scoped access" policy, `cmd = ALL`, both `qual` and
  `with_check` = `(store_id = current_store_id())`, same pattern as the
  others. The earlier "no policies at all" note in this doc was stale
  by the time it was rechecked — no action was actually needed.
- **Cart persistence** — still an open decision (leaning ephemeral/
  local-only per the original sketch; not revisited this round).
- **Offline behavior** — still an open decision, not addressed.

## Phases

### Phase A — Supabase project setup — DONE
- [x] Supabase project created
- [x] `supabase_flutter` added to `pubspec.yaml`
- [x] Client initialized once in `main.dart`, before `runApp`

### Phase B — Schema design — DONE (for the tables below)
- [x] `categories` table (RLS: store scoped access, ALL)
- [x] `products` table (RLS: store scoped access, ALL)
- [x] `staff_users` table — `id, store_id, name, pin_hash, role,
      is_active, failed_attempts, locked_until` (RLS: store scoped
      access, ALL)
- [x] `stores`, `store_members`, `store_counters` tables exist
- [x] `transactions`, `transaction_line_items` tables exist
- [x] `store_counters` RLS confirmed already correct (`ALL`, scoped to
      `current_store_id()`) — no action needed

### Phase C — Auth model decision — DONE
Resolved as Option 2 (shared owner session + PIN-gated table — see
above). `pgcrypto` is used for PIN hashing (`extensions.crypt` /
`extensions.gen_salt('bf')` — schema-qualified, since Supabase installs
pgcrypto into the `extensions` schema, not `public`).

### Phase D — Migrate `ProductProvider` — DONE (per earlier work)
- [x] `ProductProvider.loadFromSupabase()` exists and is called
      fetch-once-on-login, right after a successful PIN sign-in and
      before `HomeShell` shows.
- [ ] Not reverified this round whether `addProduct`/stock
      methods/category CRUD are fully Supabase-backed or partially
      still in-memory — worth a quick check next time this area comes
      up.

### Phase E — `CartProvider` — NOT STARTED
- [ ] Decision not revisited: ephemeral/local vs. persisted

### Phase F — Migrate `TransactionProvider` — DONE
- [x] `models/transaction.dart` — added optional `id` field
      (Supabase row id), everything else unchanged, non-breaking.
- [x] `record_transaction(p_total, p_cash_tendered, p_change_amount,
      p_cashier_name, p_items jsonb)` RPC — inserts one `transactions`
      row plus one `transaction_line_items` row per cart item
      atomically (both inserts share the function's implicit
      transaction, so a failed line-item insert rolls back the sale
      row too). `security invoker` — RLS applies normally through
      `set_store_id`, no privilege escalation needed since staff share
      the owner's real Auth session.
- [x] **Trigger-ordering bug found and fixed.** Postgres fires
      same-timing `BEFORE INSERT` triggers on one table in alphabetical
      order *by trigger name*. `trg_assign_transaction_number` sorted
      before `trg_transactions_set_store_id`, so the transaction-number
      trigger ran first, while `NEW.store_id` was still null — threw
      `null value in column "store_id" of relation "store_counters"`.
      Fixed by renaming both triggers with numeric prefixes:
      `trg_01_set_store_id`, `trg_02_assign_transaction_number`.
- [x] `TransactionProvider.record()` — rewritten, now
      `Future<Transaction>`, calls the RPC instead of appending to an
      in-memory list.
- [x] `TransactionProvider.loadFromSupabase()` — written (nested
      select pulling `transaction_line_items` per transaction in one
      request), **not yet wired into any call site** — see Phase F
      follow-up below.
- [x] `checkout_modal.dart` (`_confirm()`) — updated call site: now
      awaits `record()`, catches failure (shows an in-modal error
      instead of silently clearing the cart/deducting stock/closing as
      if the sale succeeded), disables the confirm button and shows a
      spinner while the request is in flight.
- [x] `transaction_detail_modal.dart` — checked, needs no changes
      (only reads fields that didn't move or change type).
- [x] **Verified end-to-end with a real checkout in the running app**
      (not just SQL Editor). Confirmed via Table Editor: `transactions`
      row landed with correct `transaction_number` (1), `store_id`,
      totals; matching `transaction_line_items` row landed with
      correct `product_id`, `product_name`, `category`, pricing.

#### Phase F follow-up (not yet done, blocks calling this fully wired)
- [x] `TransactionProvider.loadFromSupabase()` — **RESOLVED.** Wired
      into `login_screen.dart`, run in parallel with
      `ProductProvider.loadFromSupabase()` via `Future.wait([...])`
      right after `verify_staff_login()` succeeds, before
      `widget.onLogin(matched)` is called.
- [x] `cashier_name` — **RESOLVED.** Now captured end-to-end:
      `HomeShell` (holds the logged-in `AppUser`) passes
      `cashierName: widget.user.name` into `RegisterScreen`, which
      passes it to `CheckoutModal.show(..., cashierName: ...)`, which
      passes it to `TransactionProvider.record(..., cashierName: ...)`,
      which sends it as `p_cashier_name` to the RPC. Also added
      `cashierName` to the `Transaction` model itself and populated it
      in both `record()`'s return value and `loadFromSupabase()`'s
      row-mapping, so it round-trips for display, not just write-only.
      Note: `CheckoutModal.show()`'s signature changed from a
      positional optional `[VoidCallback? onComplete]` to named
      `{String? cashierName, VoidCallback? onComplete}` — the one
      existing call site (`register_screen.dart`) was updated to match.

#### Phase F extension — offline queue (added after F was otherwise closed)
The "Offline behavior — still an open decision" line above was resolved
this round, at least for checkout: a sale that can't reach Supabase no
longer blocks checkout or gets lost.

- [x] `models/pending_sale.dart` (new) — a locally-persisted sale
      snapshot (items, totals, cashier, timestamp), JSON-encoded to
      SharedPreferences as a single list under one key.
- [x] `models/transaction.dart` — added `localId` (tags an unsynced
      row back to its queue entry) and `isPending` getter (`id == null`).
- [x] `TransactionProvider.record()` — on a network-shaped failure
      (anything except `PostgrestException`/`AuthException`, since
      those mean the server actually responded and a retry won't
      help), queues the sale locally instead of throwing, and returns
      a `PENDING` placeholder `Transaction` rather than failing
      checkout. A real rejection still rethrows as before.
- [x] `TransactionProvider.syncPending({deductStock})` — replays the
      queue against `record_transaction`; on success swaps the
      placeholder for the real synced row and (via the passed-in
      callback) triggers stock deduction for that sale at the moment
      it actually lands, not before.
- [x] `checkout_modal.dart` — `CheckoutResult` enum
      (`cancelled` / `completedSynced` / `completedQueued`) threads
      through `show()`'s `onComplete` so the caller can word the
      confirmation differently for a queued sale. Also fixed a
      fire-and-forget bug this round introduced: the stock-deduction
      call wasn't being awaited, so its own try/catch wasn't actually
      catching anything.
- [x] `product_provider.dart` — added
      `deductStockForLineItems(List<TransactionLineItem>)`, a
      snapshot-based twin to `deductStockForSale` for use when a
      queued sale syncs later and there's no live `CartItem`/`Product`
      left, only the flat record that was persisted to disk.
- [x] `login_screen.dart` — `loadFromSupabase()` no longer
      auto-triggers `syncPending()` internally (would've run without
      the stock-deduction callback wired in); the caller now calls
      `syncPending(deductStock: ...)` explicitly right after both
      providers finish loading.
- [x] `register_screen.dart` / `home_shell.dart` — updated for the
      `CheckoutResult`-based `onComplete` signature and cashier-name
      threading (see the cashier_name entry above).

**Explicitly NOT done / still open on the offline queue:**
- No retry trigger faster than "next login" — a sale queued mid-shift
  stays queued until the next sign-in, not the moment connectivity
  actually returns. A connectivity-listener package (e.g.
  `connectivity_plus`) would close this; not added.
- No give-up/discard path for a permanently-failing queued entry (e.g.
  a product deleted between queueing and syncing) — it retries forever
  with no manual "discard" option.
- Nothing in the UI surfaces `pendingCount` yet (a badge, a banner) —
  the only visible sign of a queued sale right now is its `#PENDING`
  row in the Transactions tab.
- Not yet tested against a real device with real airplane-mode /
  flaky-wifi conditions — only reasoned through, not run.

#### Phase F bug fix this round — transaction timestamps displayed in UTC, not local time
Supabase's `created_at` is stored and returned in UTC, but every read
path in `transaction_provider.dart` was parsing it with
`DateTime.parse(...)` and using it as-is — so `transactions_panel.dart`
and `transaction_detail_modal.dart` were displaying raw UTC clock time
against a Philippine (UTC+8) device, and `dailySummaries`' "Today" /
"Yesterday" day-bucketing was grouping sales by the wrong calendar day
near midnight.
- [x] `record()` — `.toLocal()` added after parsing the RPC's
      `created_at`
- [x] `syncPending()` — same, for a queued sale's timestamp once it
      syncs
- [x] `_fromRow()` — same, for every historical transaction loaded on
      login
No changes needed in `transactions_panel.dart` or
`transaction_detail_modal.dart` — they just read `.hour`/`.minute`/
`.day` off whatever `DateTime` they're given, so converting at the one
entry point (`transaction_provider.dart`) fixes display and day-
grouping everywhere downstream.


- [x] First-run owner setup: `StoreSetupScreen` (create store via
      `signUp()` + `store_name` metadata → `handle_new_user` trigger
      creates `stores`/`store_members`/seeded `Uncategorized` category
      atomically; or sign in via `signInWithPassword()` on a new
      device/reinstall)
- [x] Owner onboarding: `AddSelfAsStaffScreen`, shown once when
      `staff_users` is empty for the store — calls `add_staff_user()`
      to seed the owner's own staff row (role `admin`)
- [x] Staff PIN login: existing `LoginScreen` now checks against
      `verify_staff_login()` RPC instead of an in-memory list
- [x] `main.dart` routes on Supabase auth state + `staff_users`
      emptiness (`StreamBuilder<AuthState>` → `FutureBuilder<bool>`)
- [x] Users admin panel (`users_panel.dart` / `user_provider.dart`,
      Settings → Users) rewired from a pure in-memory list to real
      Supabase-backed add/edit/soft-delete
- [x] New `update_staff_user()` RPC added (name/role always updatable;
      PIN rehashed only if a new one is provided — blank means "keep
      current")
- [x] Delete/remove in the Users panel is a soft delete
      (`is_active = false`), matching what `verify_staff_login()`
      already checks — not a hard `DELETE`

### Phase H — Storage — IN PROGRESS

- [x] Bucket `product-images` created (public read)
- [x] Storage RLS policies added: writes scoped to the caller's own
      `auth.uid()` folder (`storage.foldername(name)[1] =
      auth.uid()::text`); reads public
- [x] `products.image_url` column added (`text`, nullable)
- [x] `models/product.dart` — `imageBytes: Uint8List?` replaced with
      `imageUrl: String?` (a persisted Storage URL instead of
      in-memory bytes that never survived a reload)
- [x] `product_provider.dart` — new `_uploadProductImage(productId,
      bytes)` helper uploads to `product-images/{uid}/{productId}.jpg`
      (`upsert: true`, so replacing a photo overwrites rather than
      accumulating orphaned files) and returns the public URL
- [x] `addProduct()` — uploads the photo (if provided) right after
      insert, using the new row's id; a failed upload/save doesn't
      fail the whole add — the product is just created without a
      photo, re-addable via the camera badge afterward
- [x] `updateProductImage()` — rewritten from a local-only `Uint8List`
      setter into a real async Storage upload + `products.image_url`
      persist
- [x] `widgets/product_card.dart` — `Image.memory(imageBytes)` →
      `Image.network(imageUrl)`, with a loading spinner and an emoji
      fallback (`errorBuilder`) if the image fails to load
- [x] `screens/register_screen.dart` — both image-upload call sites
      (`onImageSelected` in edit mode, and `AddProductDialog.onSubmit`)
      now `.catchError(...)` and show a snackbar on failure instead of
      failing silently

**Bug found this round, fix in progress — uploaded photos not
surviving a fresh reload:**
- Symptom: a photo uploaded for an existing product (e.g. "Red Horse")
  displayed correctly for the rest of that session, but was gone after
  a hot restart / fresh login.
- Confirmed via Table Editor: `products.image_url` was `null` for that
  row — the Storage upload itself succeeded (which is why it displayed
  in-session, from local provider state), but the follow-up
  `.update({'image_url': ...})` on `products` never actually
  persisted.
- `updateProductImage()` and `addProduct()` now both chain `.select()`
  after the `image_url` update and throw if zero rows come back —
  Supabase doesn't raise an exception when RLS silently blocks an
  `UPDATE`, it just matches 0 rows and returns success, so this makes
  a blocked write surface as a real, catchable error (→ the
  register_screen snackbar above) instead of failing invisibly.
- **Not yet confirmed fixed.** This change makes the failure
  *visible*, not necessarily *fixed*. Next step: re-test the upload —
  if the "Photo upload failed" snackbar now appears, pull `products`'
  actual `UPDATE` RLS policy (`select * from pg_policies where
  tablename = 'products'`) and correct it there.

### Phase I — AI admin assistant — NOT STARTED (stretch, optional)

## Session log — bugs found and fixed this round
- `models/transaction.dart` shipped without the `id` field added
  during a prior edit (edit apparently didn't get saved into the
  actual project file) — caused a build error, "No named parameter
  with the name 'id'", in `transaction_provider.dart`. Fixed by
  re-applying the `id` field/constructor param directly against the
  actual current file content.
- Trigger firing order on `transactions` (see Phase F above) — the
  more consequential bug this round; not a typo, a genuine ordering
  dependency between two `BEFORE INSERT` triggers that Postgres
  doesn't make obvious unless you know to check alphabetical-by-name
  ordering.
- (This round) Transaction timestamps displayed in UTC instead of
  local Philippine time — see Phase F bug fix above.
- (This round) Uploaded product photos not surviving a reload —
  `image_url` never actually persisted to `products` despite the
  Storage upload succeeding, because Supabase doesn't error on an
  RLS-blocked `UPDATE`, it just silently matches zero rows. Added a
  `.select()`-and-check after every `image_url` write so this now
  surfaces as a real error — see Phase H above. Root RLS policy fix
  itself still pending confirmation.
- (This round, not Supabase-related) `product_card.dart` threw a
  `RenderFlex overflowed` error at very small card sizes (many grid
  columns × a narrow window) — the name/price block used fixed-height
  `SizedBox`es, which a `Column` always lays out at their exact
  requested size regardless of how little room is actually available;
  only the single `Expanded` (the image) was actually flexible. Fixed
  by wrapping the name/price block in `Flexible` + `FittedBox(fit:
  BoxFit.scaleDown)` so it shrinks together instead of overflowing.

## How to resume
Tell Claude: "continue the Kahapro Supabase integration — start
[Phase X]." Upload this file at the start of a fresh conversation so
context carries over. Worth prioritizing next: confirm whether the
Phase H `image_url` RLS fix actually surfaces the write failure on
re-test — if it does, upload the `products` table's RLS policies (or
just describe them) so the `UPDATE` policy itself can be fixed;
`updateProductImage()` and `addProduct()` are ready to persist
correctly the moment that policy allows the write through. After that:
`store_counters` RLS (Phase B, believed resolved but from an earlier
round), confirming Phase D's actual completeness, and settling the
Cart persistence / offline decisions before Phase E work begins in
earnest.
