# Kahapro → Supabase Integration — sketch plan

## Goal
Replace the four in-memory `ChangeNotifier` providers (`ProductProvider`,
`CartProvider`, `TransactionProvider`, `UserProvider`) with real
persistence on Supabase (Postgres + Auth + Storage), and add an AI admin
assistant using the same provider-fallback pattern already proven in
UpaPro's "Agent Ria" (Gemini → Groq → Mistral), rehosted as a Supabase
Edge Function instead of a Firebase Cloud Function.

This is a **sketch plan** — a scaffold for decisions and sequencing, not
a locked spec. Nothing below has been built yet.

## Where things stand today (before this track)
- All four providers are in-memory only — state resets on every restart.
- Auth (`login_screen.dart`) matches an entered name (case-insensitive)
  + PIN against `UserProvider`'s in-memory account list. No real session,
  no hashing.
- Categories are a real stored list on `ProductProvider`
  (`categoryNames`, `addCategory`/`renameCategory`/`deleteCategory`),
  with a permanent locked `Uncategorized` fallback bucket.
- Transactions are logged with immutable line-item snapshots and a
  ledger-style display number (`#00001`, `#00002`, …).
- Login is name + PIN, not email/password — worth keeping in mind since
  that's not Supabase Auth's default shape (see Phase C).

## Scope
1. **Auth** — replace the placeholder PIN check with something backed
   by Supabase
2. **Database** — Postgres tables behind each provider's data
3. **Storage** — Supabase Storage for product photos (currently
   in-memory `Uint8List`)
4. **AI admin assistant** (stretch, optional) — Edge Function fallback
   chain, tool-calling over the new tables

## Open decisions — settle these before writing code

- **Auth model** (see Phase C) — real per-staff Supabase Auth accounts,
  vs. one shared/service session with PIN checked against a table
  (keeps today's UX, but isn't "real" auth in the Supabase sense)
- **Schema** — table names, PK types (uuid vs the current string ids
  like `p_...`, `u_...`), how the `#00001` ledger numbering maps to
  Postgres (identity column vs a separate counter)
- **RLS policies** — who can read/write what; matters more once real
  staff accounts exist with different roles (admin vs cashier)
- **Cart persistence** — does `CartProvider` need to survive app
  restart, or does only the *completed* transaction need to persist?
  (Leaning toward: cart stays ephemeral/local, only checkout writes to
  Supabase — flagged here as a decision, not a conclusion.)
- **Offline behavior** — Paupahan/UpaPro uses a local-first
  IndexedDB-outbox pattern for spotty connectivity. Does a register
  terminal losing connection mid-sale need the same treatment, or is
  that overkill for Kahapro's usage pattern?
- **Migration order** — which provider goes first. Suggested order
  below follows dependency order (categories/products before
  transactions, since transactions reference products at sale time).

## Phases

### Phase A — Supabase project setup
- [ ] Create the Supabase project, capture project URL + anon key
- [ ] Add `supabase_flutter` to `pubspec.yaml`
- [ ] Initialize the client once in `main.dart`, before `runApp`
- [ ] Decide where secrets live (not hardcoded in the repo)

### Phase B — Schema design
- [ ] `categories` table
- [ ] `products` table (incl. `stock_qty`, `low_stock_threshold`)
- [ ] `transactions` + `transaction_line_items` tables (keep the
      immutable-snapshot behavior — line items store name/price/qty/
      category as copied values, not live FKs, so past sales don't
      retroactively change if the catalog changes later)
- [ ] `staff_users` table (name, role, PIN or auth link — depends on
      Phase C)
- [ ] Decide id strategy per table (uuid default vs preserving the
      current human-readable schemes)

### Phase C — Auth model decision
Two real options, worth deciding explicitly rather than defaulting:

- **Option 1 — Real Supabase Auth per staff member.** Each cashier/
  admin gets a genuine Supabase Auth account (likely email + password,
  or email + magic link). Closest to "real" auth; changes the login UX
  away from name+PIN.
- **Option 2 — Shared session + PIN-gated table.** The app authenticates
  once with a single Supabase Auth identity (or service-role key behind
  an Edge Function), and staff login stays name+PIN checked against the
  `staff_users` table, same UX as today. Simpler migration, but PINs
  aren't real per-user auth — more like today's placeholder, just
  persisted.

No decision made yet — flag for discussion once this phase starts.

### Phase D — Migrate `ProductProvider` (catalog, categories, stock)
- [ ] Point `categoryNames`/`addCategory`/`renameCategory`/
      `deleteCategory` at Supabase instead of the in-memory list
- [ ] Point `products`/`addProduct`/stock methods at Supabase
- [ ] Decide whether `Uncategorized` is seeded as a real row or handled
      specially in code (it's currently protected in-app — same
      protection needs to hold against direct table access too, via RLS
      or a check constraint)

### Phase E — `CartProvider`
- [ ] Decide (per open decision above) whether this needs a Supabase
      table at all, or stays local/in-memory since it's transient until
      checkout

### Phase F — Migrate `TransactionProvider`
- [ ] Write completed sales to `transactions` +
      `transaction_line_items`
- [ ] Preserve the ledger-numbering behavior
- [ ] Preserve `dailySummaries`-style rollups (as a query instead of an
      in-memory grouping)

### Phase G — Migrate `UserProvider` / staff accounts
- [ ] Depends entirely on the Phase C decision — build this only after
      that's settled

### Phase H — Storage
- [ ] Bucket for product photos, replacing in-memory `imageBytes`
- [ ] Decide public-read vs private+signed-URL (UpaPro's `tenant-docs`
      bucket uses private + short-lived `createSignedUrl()` links
      minted at render time — worth reusing that pattern here rather
      than a fully public bucket)

### Phase I — AI admin assistant (stretch, optional)
- [ ] Supabase Edge Function (Deno) instead of a Firebase Cloud
      Function — no Blaze-style gate on outbound calls on Supabase's
      free tier
- [ ] Fallback chain: Gemini → Groq → Mistral (same three providers
      discussed, same try-next-on-failure shape as UpaPro's Agent Ria)
- [ ] Tool-calling surface for Kahapro: product lookup, stock lookup,
      transaction/sales lookup, staff lookup — same shape as Agent Ria's
      tenant/payment/maintenance/unit tools, pointed at the new tables
      instead of Firestore
- [ ] Decide whether this ships alongside the initial Supabase
      migration or as a later addition once the core tables are stable

## How to resume
Tell Claude: "continue the Kahapro Supabase integration — start
[Phase X]." Upload both this file and the latest
`kahapro-Flutter-migration-plan.md` at the start of a fresh
conversation so context carries over.
