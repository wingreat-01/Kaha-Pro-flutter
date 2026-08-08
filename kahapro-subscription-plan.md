# Kahapro → Subscription Plan — sketch

## Goal
Add a paid tier to Kahapro so the AI admin assistant (Phase I, currently
unbuilt) has a sustainable cost model — its per-use API cost (Gemini →
Groq → Mistral fallback) doesn't scale for free the way the rest of the
app does. Everything else in the app (POS, inventory, offline queue,
transactions) stays free at every tier; only the AI assistant (with a
tiered credit allowance — a taste on Basic, more on Pro), a product
catalog cap, and a couple of scale-related conveniences are paywalled.

**Conversion goal, stated explicitly:** Free is deliberately not meant
to be a comfortable permanent home — the 5-product cap is the main
lever for that. A real sari-sari/food-cart store almost always carries
more than 5 SKUs, so Free functions as a working trial of the core POS
rather than a viable long-term free plan, with Basic (30 products) as
where most real stores are expected to land. Worth watching once real
usage data comes in — if 5 turns out to feel punitive rather than
trial-like and hurts signups/retention, it's an easy number to revisit
without touching the enforcement mechanism.

This is a sketch, not a locked decision — pricing is decided (see
below), but some mechanics (credit metering rule, rollover) are still
open. Treat the **feature gating** and the **enforcement architecture**
as settled; the "Open decisions" section at the end flags what's still
loose.

## The 3 plans

| | **Free** | **Basic** | **Pro** |
|---|---|---|---|
| Price (monthly) | ₱0 | ₱290/mo | ₱690/mo |
| Price (annual) | — | ₱2,900/yr (2 months free) | ₱6,900/yr (2 months free) |
| Register / checkout | ✅ | ✅ | ✅ |
| Inventory & categories | ✅ | ✅ | ✅ |
| Transactions & daily summaries | ✅ | ✅ | ✅ |
| Offline queue (already built) | ✅ | ✅ | ✅ |
| Product photos (Storage) | ✅ | ✅ | ✅ |
| Total products (all categories) | up to 5 | up to 30 | unlimited |
| Staff accounts | up to 2 | up to 5 | unlimited |
| Transaction history retention | last 30 days | last 90 days | unlimited |
| AI admin assistant | ❌ | ✅ — 10 credits/mo | ✅ — 30 credits/mo |
| Emailed cloud sync (auto backup) | ❌ | ✅ — monthly | ✅ — weekly |
| Priority support | ❌ | ❌ | ✅ |

Pricing checked against comparable Philippine/regional POS apps: Imonggo
(PH-based) charges ~$30 USD/mo (~₱1,700) per branch for its paid tier;
Loyverse's paid add-ons stack to $30-60 USD/mo (~₱1,700-3,400) for a
fuller feature set; Zobaze POS (closest in spirit — utang tracking,
GCash, sari-sari-specific) doesn't disclose pricing publicly but caps
its free tier at 100 items. ₱290/₱690 sits well under all of these,
appropriate for a more price-sensitive sari-sari-store/food-cart/
lending-office market than what those apps primarily target.

AI credit math: Gemini/Groq/Mistral-tier models cost fractions of a
cent to a few cents per query even with reasonable context, so 10-30
credits/month costs well under ₱10-20 in actual API spend per user —
healthy margin on the AI feature at these prices, with room to be
generous with credit counts without threatening unit economics. For
calibration, ChatGPT Plus runs ~₱1,000/month in the Philippines — Pro
at ₱690/month bundling a full POS *and* AI credits reads as strong
value against that anchor, not overpriced.

1 credit = 1 AI chat prompt/response (not 1 token or 1 API call
under the hood — a single user-facing exchange). Whether a
multi-turn back-and-forth burns 1 credit for the whole exchange or 1
credit per message is still open — leaning toward "1 credit per
user message sent" since that's the simplest to explain and to meter
server-side (increment on each request the Edge Function accepts,
checked against the store's remaining balance for the month).

## Why gate the AI assistant specifically
Every other feature in Kahapro costs you the same flat Supabase bill no
matter how many stores use it. The AI assistant is the one feature
whose cost scales directly with usage (every query is a paid call to an
LLM provider). Gating *that* feature — rather than, say, product count
or staff seats — means the thing you're charging for is also the thing
that actually costs you money per use. It's also an easy pitch to
customers: "run your store" is free, "let AI help you run it smarter"
is the upsell.

## Schema additions

```sql
-- One column on stores, not a separate subscriptions table to start —
-- simplest thing that works. A real subscriptions table (with billing
-- provider, renewal date, etc.) can replace this later without
-- changing how the rest of the app reads the plan, as long as
-- current_store_id()'s plan lookup stays the same shape.
alter table stores
  add column plan text not null default 'free'
    check (plan in ('free', 'basic', 'pro'));

alter table stores
  add column plan_expires_at timestamptz; -- null = doesn't expire (e.g. free tier)

-- AI credit tracking — separate from `plan` itself since credits reset
-- monthly while plan doesn't. ai_credits_remaining counts DOWN from
-- the tier's monthly allotment (10 for basic, 30 for pro); a cron job
-- or a check-and-reset-if-stale read (see current_store_ai_credits()
-- below) resets it to the tier's full allotment at the start of each
-- billing cycle.
alter table stores
  add column ai_credits_remaining int not null default 0;

alter table stores
  add column ai_credits_reset_at timestamptz; -- when the current allotment was granted

create or replace function ai_credit_allotment(p_plan text)
returns int
language sql
immutable
as $$
  select case p_plan
    when 'basic' then 10
    when 'pro' then 30
    else 0
  end;
$$;
```

Simple decrement-and-check RPC, called by the Edge Function (not
directly by the Flutter app — see below):

```sql
create or replace function consume_ai_credit()
returns boolean -- true if a credit was available and consumed
language plpgsql
security invoker -- runs as the caller, RLS scopes it to their store
as $$
declare
  v_store_id uuid := current_store_id();
  v_plan text;
  v_remaining int;
  v_reset_at timestamptz;
begin
  select plan, ai_credits_remaining, ai_credits_reset_at
    into v_plan, v_remaining, v_reset_at
    from stores where id = v_store_id
    for update; -- lock the row so two rapid requests can't both pass the check

  -- Monthly reset, lazily on first use of a new cycle rather than a
  -- cron job — simpler to reason about, no scheduled job to maintain.
  if v_reset_at is null or v_reset_at < date_trunc('month', now()) then
    v_remaining := ai_credit_allotment(v_plan);
    v_reset_at := now();
  end if;

  if v_remaining <= 0 then
    update stores set ai_credits_remaining = 0, ai_credits_reset_at = v_reset_at
      where id = v_store_id;
    return false;
  end if;

  update stores set ai_credits_remaining = v_remaining - 1, ai_credits_reset_at = v_reset_at
    where id = v_store_id;
  return true;
end;
$$;
```

## Enforcement — server-side, in the Edge Function

**The critical rule: the Flutter app hiding the AI button is UX, not
security.** A basic-tier user could still call the AI Edge Function
directly (skipping the app entirely — anyone can hit a Supabase Edge
Function URL with `curl` and a valid JWT) and rack up real API costs on
your dime if the *function itself* doesn't check the plan. The gate has
to live server-side, checked before any tokens get spent, every single
call — not just once at login, since a plan can lapse mid-session.

Sketch of the Edge Function (`supabase/functions/ai-assistant/index.ts`):

```ts
// Pseudocode — actual provider-fallback logic (Gemini → Groq →
// Mistral) mirrors UpaPro's Agent Ria pattern, omitted here since
// that part doesn't change based on this plan.

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization');
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  // 1. Try to consume one credit under the caller's own RLS-scoped
  //    session — this single RPC call handles the free-tier check
  //    (0 credits, always false), the monthly reset, and the
  //    decrement, all in one row-locked transaction so two rapid
  //    requests can't both slip through on the last credit.
  const { data: creditGranted, error } = await supabase.rpc('consume_ai_credit');

  if (error) {
    return new Response(JSON.stringify({ error: 'Could not verify AI access.' }), { status: 500 });
  }

  // 2. Gate BEFORE calling any AI provider — this is the actual
  //    security boundary, not the Flutter UI. A Free-tier store
  //    always has 0 credits (ai_credit_allotment('free') = 0), so
  //    this single check covers both "wrong tier" and "used up this
  //    month's credits" without a separate plan lookup.
  if (!creditGranted) {
    return new Response(
      JSON.stringify({ error: 'No AI credits remaining this month. Upgrade or wait for next cycle.' }),
      { status: 403 },
    );
  }

  // 3. Only now, spend a real API call.
  const { prompt } = await req.json();
  const aiResponse = await callWithFallback(prompt); // Gemini → Groq → Mistral
  return new Response(JSON.stringify(aiResponse), { status: 200 });
});
```

Key points baked into that sketch:
- Uses the **caller's own JWT** (via `Authorization` header passthrough),
  not a service-role key — so RLS on `stores` does the same
  store-scoping work it already does everywhere else in the app. No new
  trust boundary to design.
- The credit check happens **before** any provider call — a rejected
  request costs you nothing.
- `consume_ai_credit()` row-locks (`for update`) so a store can't burn
  more credits than it has by firing several requests in quick
  succession before any of them commit.
- Returns a plain `403` the app can catch and turn into a normal
  "No AI credits remaining — upgrade or wait for next cycle" message —
  same pattern as the existing `PostgrestException`/`AuthException`
  handling already in `transaction_provider.dart`'s
  `_isLikelyNetworkFailure`.

## Enforcement — product limit (database trigger, not the Edge Function)

Different mechanism from the AI assistant, because the access path is
different: products are written directly from the Flutter app straight
to Postgres (via `ProductProvider`), there's no Edge Function in that
path to put a check in. So this has to be a database-level guard — a
`before insert` trigger on `products` — or, same as the AI credits
story, a Free-tier user could hit the Supabase REST/Postgrest API
directly and insert past the cap regardless of what the Flutter UI
shows or hides.

```sql
create or replace function product_limit(p_plan text)
returns int
language sql
immutable
as $$
  select case p_plan
    when 'free' then 5
    when 'basic' then 30
    else null -- null = unlimited (pro)
  end;
$$;

create or replace function enforce_product_limit()
returns trigger
language plpgsql
security invoker -- RLS on products already scopes reads by store
as $$
declare
  v_plan text;
  v_limit int;
  v_count int;
begin
  select plan into v_plan from stores where id = new.store_id;
  v_limit := product_limit(v_plan);

  if v_limit is not null then
    select count(*) into v_count from products where store_id = new.store_id;
    if v_count >= v_limit then
      raise exception 'Product limit reached for % plan (% max). Upgrade to add more products.',
        v_plan, v_limit
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_enforce_product_limit
  before insert on products
  for each row execute function enforce_product_limit();
```

Key points:
- Runs on every insert, not just ones that go through the app's "add
  product" dialog — same "server-side, always, not just at login"
  principle as the AI credit check.
- Free/Basic caps come from `product_limit()`; Pro returns `null`
  meaning unlimited, so the count check is skipped entirely for Pro —
  no need to special-case "unlimited" as a magic huge number.
- Raises a Postgres exception with a clear message on the last insert
  attempt over the cap; Flutter-side, this surfaces as a
  `PostgrestException` the app can catch (same
  `_isLikelyNetworkFailure`-style handling already used for other
  Postgrest/Auth exceptions in `transaction_provider.dart`) and turn
  into an "Upgrade to add more products" prompt rather than a raw
  error.
- Deliberately **not** row-locked like `consume_ai_credit()` — a
  `count(*)` race at the exact moment a store is one product under its
  cap is low-stakes (worst case, one or two extra products briefly
  slip through), unlike AI credits where every over-limit call is a
  real, uncapped-cost API charge. Not worth the extra locking
  complexity here.

## Flutter-side changes (UX only, not the real gate)
- `stores.plan` and `ai_credits_remaining` fetched alongside the rest
  of store data on login (wherever `current_store_id()`-scoped data
  already loads — natural fit next to
  `ProductProvider.loadFromSupabase()` / login flow).
- AI assistant entry point (chat icon, admin panel section — wherever
  Phase I ends up living) hidden or shown as "🔒 Pro" for Free-tier
  stores; for Basic/Pro, shows remaining credits this cycle (e.g.
  "7/10 credits left") so a cashier or owner isn't surprised by a 403
  they have to interpret themselves.
- A simple upgrade screen/flow — even just a link out to wherever
  billing is handled — for the moment someone taps a locked entry
  point or runs out of credits mid-cycle.
- Add-product dialog/flow shows a running count against the cap for
  Free/Basic (e.g. "4/5 products") and disables/hides the "Add
  product" action once at the limit, catching the trigger's exception
  and surfacing it as the same "Upgrade to add more products" prompt
  if a race lets the request through anyway.

## Billing — not designed yet, flagged as its own decision
Given the plan to publish on Google Play, **Google Play Billing** is
the natural fit for in-app subscriptions on Android (handles receipts,
renewals, cancellations, and refunds without building that
infrastructure yourself). That integration — verifying a Play Billing
purchase server-side and updating `stores.plan` accordingly — is a
separate, sizeable piece of work not sketched here. Worth its own pass
once the plan/gating shape above is settled.

## Suggested build order
1. `stores.plan` column + `current_store_plan()` helper (small, no
   app-facing change yet — everyone defaults to `free`).
2. Build Phase I (the AI assistant Edge Function) **with the plan check
   built in from the start**, not bolted on after — per the earlier
   discussion, this is a pre-Phase-I decision precisely because it
   changes the function's shape.
3. Flutter-side: fetch `plan`, hide/lock the AI entry point accordingly.
4. Google Play Billing integration + a way to manually flip a store's
   plan in Supabase (for testing, and for handling support requests
   before billing is fully automated).

## Status: paid tier on hold — launching free-only
Decision (see conversation): for initial launch, skip the paid
subscription entirely — Free/Basic/Pro stays a **future option**, not
built now. All stores run on the Free tier as sketched above, with the
AI assistant using the Gemini → Groq → Mistral fallback chain, no
credit gating, no `stores.plan` enforcement live yet. The schema,
Edge Function, and RPC sketches above are kept as-is so this can be
switched on later without a redesign — just flip the plan default,
wire up the `consume_ai_credit()` check in the Edge Function, and ship
the Flutter-side lock/upgrade UI already sketched.

## Scaling considerations (free-only launch, 50-100 clients)

**Supabase free tier** — comfortably fine on raw capacity at this
scale (500 MB DB, 1 GB storage, 5 GB egress, unlimited API requests).
POS transaction rows are small text, so 50-100 stores won't stress the
database size limit any time soon; product photos in Storage are the
one thing to watch as it grows toward the 1 GB cap over time.

The bigger risk isn't capacity, it's **no backups, no SLA** on the
free tier. Once real stores have real sales data in that database, a
bad migration or a Supabase-side incident with nothing to restore from
means permanent data loss for someone's business — not a "ran out of
rows" problem. Moving to Supabase Pro ($25/mo) is worth treating as a
business-continuity decision the moment paying/real-usage customers
are on it, independent of whether the free tier's numeric limits have
actually been hit.

**The AI free tiers (Gemini/Groq/Mistral) are shared across the whole
app**, not per-client — one account backs every store combined, so
what matters is total traffic across all clients against the combined
ceiling, not any single store's usage:
- Gemini Flash: 1,500 requests/day, 15 requests/minute, project-wide
- Groq: roughly 1,000-14,400 requests/day depending on model, 30
  requests/minute, org-wide
- Mistral API free tier: 1 request/second, 500,000 tokens/minute, 1
  billion tokens/month, workspace-wide — the most generous of the
  three

With no credit gating (free-only launch), usage is harder to bound
than the earlier 30-credits/mo Pro-tier math, so daily totals matter
less here than **burst behavior**: if many store owners use the
assistant in the same few minutes (e.g. everyone checking it around
store-opening time), Gemini's 15 RPM ceiling is the one that could get
hit first. The fallback chain is exactly what absorbs that — a 429
from Gemini should spill to Groq (30 RPM) automatically — so it's
worth confirming the Edge Function actually implements real failover
(catches the 429 and retries against the next provider) rather than a
single try with no fallback path, since that failover is now the only
thing standing between a burst and a visible error, with no credit
system to soften demand.

**Watch-point specific to launching without gating:** without a
credit ceiling, a single unusually chatty store (or a bug that loops
requests) can consume a disproportionate share of the shared daily/RPM
budget and degrade the experience for every other store on the same
free-tier account. Worth keeping an eye on per-store request volume
once real usage starts, even informally, since it's the thing the
credit system would otherwise have contained.

## Data backup & portability

Three separate things, easy to conflate but solving different problems
— server-side backup is the actual safety net; export/import and
email sync are client-facing features layered on top, not substitutes
for it.

### 1. Server-side DIY backup (the real safety net — build this first, free)
Not client-facing at all — a scheduled job, invisible to store owners,
that protects the business regardless of what any individual owner
does.

- **Mechanism:** GitHub Actions on a daily cron schedule, running
  `pg_dump` against the Supabase direct connection (port 5432, not the
  pooler), pushing the resulting `.sql` file to Cloudflare R2 (free
  tier is generous and has no egress fees) or another object store.
  Zero recurring cost.
- **Retention:** keep a rolling window (e.g. last 14-30 daily dumps)
  rather than every dump forever, so storage doesn't grow unbounded.
- **Covers Postgres only** — the product-photos Storage bucket is a
  separate surface and needs its own sync/copy if it's worth
  protecting the same way.
- **Known gap vs. Supabase Pro:** a nightly dump can lose up to ~24h
  of transactions if something goes wrong right before the next run.
  Pro's point-in-time recovery (PITR) closes that gap — worth
  upgrading to once real customer sales data is on the line, per the
  Scaling considerations section above. The DIY dump is the
  free stopgap until then, not the end state.
- **Test the restore, not just the backup** — do one real restore into
  a throwaway Supabase project to confirm the dump actually works end
  to end (schema, RLS policies, data) before relying on it.

### 2. Export Data (client-facing, Phase addition)
A "Download my data" action in Settings — CSV/Excel of transactions,
inventory, and daily summaries for the signed-in store. Available at
every tier, not paywalled — it's a transparency and trust feature
first (addresses owners not realizing their data lives in a database
somewhere) and a personal safety net second (accountant handoff, tax
filing, peace of mind for owners who want their own copy).

Not a substitute for the server-side backup above — it only helps
owners who actually remember to run it, which historically is a small
fraction of any app's users. Keep it billed internally as "nice extra
+ transparency," not as the data-loss plan.

### 3. Import Data — worth building, but scope it carefully
Letting an owner import prior sales/transaction history (e.g.
switching from a paper ledger or another POS) is genuinely useful, but
it's the riskiest of the three to get wrong, specifically because of
how transactions are currently modeled:

- Transactions are logged as **immutable, ledger-numbered entries**
  (`assign_transaction_number` trigger incrementing `store_counters`
  per store). A naive bulk import that inserts rows directly would
  either collide with that numbering sequence or require faking
  numbers for historical data that were never actually assigned by the
  store's own counter — either way it blurs "what the POS actually
  recorded" with "what got backfilled," which matters for daily
  summaries, reporting, and trust in the ledger.
- **Recommended v1 scope: products/inventory import only** (CSV of
  product name, price, category, stock) — lower risk, immediately
  useful for onboarding a store's existing catalog, no ledger
  implications at all.
- **Transaction/sales history import, if built, should be v2 and
  clearly separated from the live ledger** — e.g. tagged with a
  `source = 'imported'` column and excluded from (or clearly flagged
  in) `assign_transaction_number`'s sequence, so imported historical
  rows never look indistinguishable from transactions the POS itself
  recorded. Needs its own validation pass (duplicate detection,
  malformed rows, date sanity checks) before it's safe to expose to
  non-technical users uploading arbitrary CSVs.
- Not part of the initial build order below — flagged here as a
  follow-on once Export ships and the ledger-safety approach is
  actually designed, not sketched yet.

### 4. Emailed cloud sync — subscription-gated convenience
Reuses the Export engine (#2) plus a delivery cron + email provider
(e.g. Resend/Postmark) to automatically email a store's owner their
data on a schedule — no action required from them, which covers the
"owners who won't remember to export manually" gap that #2 alone
doesn't solve.

- Fits naturally into the existing plan-gating architecture (see
  Enforcement section above) as a second paywalled convenience
  alongside the AI assistant — Free gets none, Basic gets a monthly
  email, Pro gets weekly (see updated plan table above).
- Low marginal cost to build once Export exists — it's the same CSV
  generation, triggered by a scheduled Edge Function/cron instead of a
  button tap, attached to an outbound email.
- Still not a replacement for the server-side DIY backup in #1 — it's
  a customer-facing convenience/reassurance feature, gated because it
  costs a little (email provider send costs, cron compute), not
  because it's the thing protecting the business from data loss.

## Open decisions
- Whether "1 credit per user message" (leaning yes, see AI credit math
  note above) is the final metering rule, vs. 1 credit per full
  multi-turn exchange — affects `consume_ai_credit()`'s call site
  (once per request vs. once per conversation) but not its shape.
- Annual vs. monthly billing, and whether Google Play Billing supports
  both cleanly for this use case — not researched yet.
- What happens to a Pro store's data access if a subscription lapses —
  does history older than Basic's 90-day window become inaccessible
  immediately, or is there a grace period? Worth deciding before it's
  a real support ticket.
- Whether unused credits roll over month-to-month or reset to zero
  (the schema above resets to the tier's full allotment each cycle,
  i.e. no rollover — simplest to reason about and explain to a
  customer, but worth confirming that's actually the intent).
