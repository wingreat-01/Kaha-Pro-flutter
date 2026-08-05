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
  `store_counters` currently has RLS enabled with **no policies at
  all** — flagged as-is in the dashboard, not yet addressed.
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
- [ ] `store_counters` RLS policy still needs to be defined (currently
      blocks all Data API access — no policies exist on it yet)

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

### Phase F — Migrate `TransactionProvider` — STATUS UNCONFIRMED
- [ ] `transactions` / `transaction_line_items` tables exist in the
      schema, but whether `TransactionProvider` actually reads/writes
      them (vs. still being in-memory) wasn't checked this round

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
- `AppUser.pin` was a required constructor param with nothing left to
  supply it post-login (PINs don't need to live in memory after a real
  sign-in) — made optional/defaulted to `''`.
- `AppUser.role` was being passed a raw `String` from the RPC result
  into a `UserRole`-typed field — added a `_parseRole()` helper on both
  `login_screen.dart` and `user_provider.dart` to convert properly,
  falling back to `cashier` on an unrecognized value rather than
  crashing.
- `add_staff_user()` and `verify_staff_login()` both called
  `crypt()`/`gen_salt()` unqualified; since Supabase installs
  `pgcrypto` into the `extensions` schema rather than `public`, both
  functions threw `function gen_salt(unknown) does not exist` until
  qualified as `extensions.crypt(...)` / `extensions.gen_salt(...)`.
  The new `update_staff_user()` function was written schema-qualified
  from the start to avoid repeating this.
- `signUp()` returning a `null` session (because "Confirm email" is
  enabled on this project, and was kept on rather than turned off) was
  silently leaving `StoreSetupScreen` looking unresponsive — added an
  explicit check that shows a "check your inbox" message and flips to
  sign-in mode.
- The Users admin panel (`users_panel.dart` + `user_provider.dart`) was
  discovered to be pure in-memory, disconnected from Supabase entirely
  — staff added through it never reached `staff_users`, so they could
  never log in. Rewired end to end (see Phase G above).

## How to resume
Tell Claude: "continue the Kahapro Supabase integration — start
[Phase X]." Upload this file and the latest
`kahapro-Flutter-migration-plan.md` at the start of a fresh
conversation so context carries over. Worth prioritizing next: closing
out the `store_counters` RLS gap (Phase B), confirming Phase D/F's
actual completeness, and settling the Cart persistence / offline
decisions before Phase E or F work begins in earnest.
