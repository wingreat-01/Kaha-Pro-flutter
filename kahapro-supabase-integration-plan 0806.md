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
- [ ] `TransactionProvider.loadFromSupabase()` is not called from
      anywhere yet — the Transactions tab will be empty in the running
      app until it's wired in. Believed to belong in
      `screens/login_screen.dart`, right alongside wherever
      `ProductProvider.loadFromSupabase()` is already awaited after
      `verify_staff_login()` succeeds and before `onLogin(user)` is
      called — `login_screen.dart` needed to confirm the exact spot
      and pattern before adding this, rather than guessing and
      duplicating/missing its existing loading or error handling.
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

### Phase G — Migrate `UserProvider` / staff accounts — DONE
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

### Phase H — Storage — NOT STARTED

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

## How to resume
Tell Claude: "continue the Kahapro Supabase integration — start
[Phase X]." Upload this file and the latest
`kahapro-Flutter-migration-plan.md` at the start of a fresh
conversation so context carries over. Worth prioritizing next:
uploading `screens/login_screen.dart` to wire
`TransactionProvider.loadFromSupabase()` in next to
`ProductProvider`'s existing call (closes out Phase F fully), then
`store_counters` RLS (Phase B), confirming Phase D's actual
completeness, and settling the Cart persistence / offline decisions
before Phase E work begins in earnest.
