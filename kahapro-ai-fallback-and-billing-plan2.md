# KahaPro — AI Fallback, Trial-Expired UI & Billing Plan

Reference doc for wiring the 6-provider AI fallback into `ai-assistant` (same base pattern as UpaPro's "Agent Ria", extended with more free-tier layers), plus the Flutter-side trial-expired experience and Google Play Billing integration.

---

## Part 1 — 6-Provider AI Fallback (Groq → Mistral → Cerebras → OpenRouter → Gemini → Premium)

Chosen so five free-tier providers get exhausted (in order of speed/generosity) before ever touching the paid premium provider. Order rationale:
- **Groq** first — fastest response time, generous free RPM, best default UX
- **Mistral** second — solid quality, prototyping-friendly free tier
- **Cerebras** third — very high throughput when its free catalog has a usable model, but catalog is volatile, so it's positioned mid-chain rather than relied on as primary
- **OpenRouter** fourth — aggregator; acts as a safety net across many free community models, not just one
- **Gemini** fifth — best free-tier *quality* (frontier-tier model) but tightest daily caps (as low as 100 RPD on 2.5 Pro), so it's saved for when earlier free tiers are exhausted rather than burned as primary
- **Premium (paid)** last — only reached if all five free tiers are exhausted; costs real money per request, so should get logged/alerted distinctly from the free-tier fallbacks

### Goal
If the primary provider fails or is rate-limited, silently fall through to the next, so a credit-holding user never sees a hard failure just because one upstream API had a bad moment.

### Where it lives
Inside the `ai-assistant` Supabase Edge Function. Order matters — **a credit is only deducted when an AI request actually succeeds**, not just because the store was eligible to try:

1. Check `store_is_read_only()` → reject early if true
2. Check credit availability *without deducting* (`has_ai_credit()`, see below) → reject if `false` (out of credits)
3. Attempt the AI call chain (Groq → Mistral → Cerebras → OpenRouter → Gemini → Premium)
4. **Only if a provider actually returns a successful response**, call `consume_ai_credit()` to deduct the credit
5. If all three providers fail, return an error to the client and **do not deduct** — the user shouldn't lose a credit for a request that never got an answer

This means `consume_ai_credit()` (already deployed) becomes the *deduct* step called after success, not the *gate* step called before attempting. It needs a companion read-only check function:

```sql
CREATE OR REPLACE FUNCTION public.has_ai_credit()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_store_id uuid := current_store_id();
  v_plan text;
  v_remaining int;
  v_reset_at timestamptz;
begin
  select plan, ai_credits_remaining, ai_credits_reset_at
    into v_plan, v_remaining, v_reset_at
    from stores where id = v_store_id;

  if v_reset_at is null or v_reset_at < date_trunc('month', now()) then
    v_remaining := ai_credit_allotment(v_plan);
  end if;

  return v_remaining > 0;
end;
$function$
```

This mirrors `consume_ai_credit()`'s lazy-reset logic (so "credits available" reads correctly even right after a monthly reset boundary) but takes **no row lock and makes no update** — it's a pure check. `consume_ai_credit()` itself doesn't change from what's already deployed; it's just called at a different point in the flow now (after success, not before the attempt).

⚠️ **Known tradeoff**: because the check (`has_ai_credit`) and the deduct (`consume_ai_credit`) are now two separate calls instead of one atomic row-locked operation, there's a small race window — two concurrent AI requests from the same store could both pass the check before either deducts, allowing credits to go slightly negative in rare concurrent-request scenarios. Given this is a single-user-per-store admin assistant (not high-concurrency), this is an acceptable tradeoff for "don't charge for failures," but worth knowing if usage patterns ever change.

Credits should be consumed once per user request, not once per provider attempt — don't re-charge the store if Gemini fails and Groq succeeds.

### Fallback chain logic

```ts
type ProviderResult = { text: string; provider: string };

async function callWithFallback(prompt: string): Promise<ProviderResult> {
  const providers = [
    { name: 'groq', fn: callGroq },
    { name: 'mistral', fn: callMistral },
    { name: 'cerebras', fn: callCerebras },
    { name: 'openrouter', fn: callOpenRouter },
    { name: 'gemini', fn: callGemini },
    { name: 'premium', fn: callPremium }, // paid — only reached if all 5 free tiers fail
  ];

  let lastError: unknown;

  for (const { name, fn } of providers) {
    try {
      const text = await fn(prompt);
      if (name === 'premium') {
        console.warn('[ai-assistant] fell through to PAID premium provider — check free-tier usage/limits');
      }
      return { text, provider: name };
    } catch (err) {
      lastError = err;
      console.error(`[ai-assistant] ${name} failed:`, err);
      // only continue the loop on retryable errors (rate limit, timeout, 5xx)
      if (!isRetryable(err)) throw err;
    }
  }

  throw new Error(`All AI providers failed. Last error: ${lastError}`);
}

function isRetryable(err: unknown): boolean {
  // 429 (rate limit), 500/502/503 (upstream failure), or network timeout
  const status = (err as any)?.status;
  return status === 429 || (status >= 500 && status < 600) || (err as any)?.name === 'TimeoutError';
}
```

### Top-level handler flow

```ts
// inside the ai-assistant edge function handler
if (await storeIsReadOnly()) {
  return jsonResponse({ error: 'Store is read-only — trial expired or subscription lapsed.' }, 403);
}

if (!(await hasAiCredit())) {
  return jsonResponse({ error: 'No AI credits remaining this cycle.' }, 403);
}

try {
  const { text, provider } = await callWithFallback(prompt);
  await consumeAiCredit(); // deduct only now — request actually succeeded
  return jsonResponse({ response: text, provider });
} catch (err) {
  console.error('[ai-assistant] all providers failed, no credit deducted:', err);
  return jsonResponse({ error: 'AI assistant is temporarily unavailable. Please try again.' }, 502);
}
```

Each `callGroq` / `callMistral` / `callCerebras` / `callOpenRouter` / `callGemini` / `callPremium` function:
- Takes the same normalized prompt input
- Returns plain text (or throws)
- Has its own timeout (recommend 15s) so one hung provider doesn't block the whole chain
- API keys pulled from Supabase secrets (`GROQ_API_KEY`, `MISTRAL_API_KEY`, `CEREBRAS_API_KEY`, `OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `PREMIUM_API_KEY`), never hardcoded

### Provider free-tier reference (as of testing, verify before relying on for production)
| Provider | Free limit | Notes |
|---|---|---|
| Groq | 30 RPM / 6K TPM / ~14,400 req/day | Fastest, open-source models only (Llama 3.3, etc.) |
| Mistral | Generous prototyping tier | Quality solid for admin-assistant use cases |
| Cerebras | ~30K TPM, very high tokens/sec | ⚠️ Free model catalog has shrunk/grown before — don't hardcode a model name without a periodic check |
| OpenRouter | 10–20 RPM per free model, many free models | Aggregator — if one free model is down, can swap to another without new integration work |
| Gemini | Flash: 15 RPM/1,500 RPD · 2.5 Pro: 5 RPM/100 RPD | Best raw quality of the free tiers, but tightest daily cap — hence positioned 5th, not 1st |
| Premium | Paid, no free cap | Only hit if all 5 free tiers fail — needs its own cost monitoring |

### Open decisions
- [ ] **Pick the premium/paid provider for tier 6** (e.g. OpenAI, Anthropic, or another paid API) — determines `callPremium`'s shape and needs its own API key + cost ceiling/alerting, since unlike tiers 1–5 this one costs money per request
- [ ] Confirm the exact model names/endpoints per provider (e.g. `llama-3.3-70b-versatile` on Groq, `mistral-small-latest`, current Cerebras free model, an OpenRouter `:free` model, `gemini-2.5-flash`) — reuse UpaPro's Agent Ria picks where they overlap
- [ ] Decide whether `provider` used should be logged per request (useful for cost tracking / debugging which provider is flaky, and for spotting when premium is getting hit too often)
- [ ] Decide per-provider timeout value (15s suggested)
- [ ] Confirm prompt/response normalization — different providers may need slightly different prompt formatting
- [ ] Cerebras catalog volatility — decide on a fallback behavior if its currently-configured free model gets deprecated (skip straight to OpenRouter?)

### Testing checklist
- [ ] Force Groq to fail (bad API key temporarily) → confirm Mistral picks up
- [ ] Force Groq + Mistral to fail → confirm Cerebras picks up
- [ ] Force Groq + Mistral + Cerebras to fail → confirm OpenRouter picks up
- [ ] Force all four free-tier-early providers to fail → confirm Gemini picks up
- [ ] Force all five free providers to fail → confirm Premium picks up, and that this event is logged distinctly (it costs money)
- [ ] Force all six to fail → confirm clean error response to Flutter (not a raw 500), and no credit deducted
- [ ] Confirm credit is only decremented once per user request, regardless of how many providers were tried
- [ ] Confirm read-only stores are rejected before any provider is called (no wasted API cost)
- [ ] Confirm a successful response (even via a late fallback provider) deducts exactly one credit

---

## Part 2 — Trial-Expired Banner + Subscribe Buttons (Flutter)

### Goal
Read-only stores already get blocked server-side (triggers). This is the UX layer: explain *why*, non-alarmingly, and offer a clear next step — without leaking a raw Postgres trigger error to the user.

### Detection
On app load / home shell init, check the store's status:
```dart
final isReadOnly = store.planExpiresAt != null && store.planExpiresAt!.isBefore(DateTime.now());
```
Mirrors `store_is_read_only()` server-side — this is a UX shortcut, not the security boundary (that's already enforced by the DB triggers).

### Banner (persistent, dismissible-but-reappearing)
Shown at the top of the home shell whenever `isReadOnly == true`:

> **Your KahaPro Pro trial has ended.**
> Your store data is safe and preserved.
> Subscribe to continue using KahaPro.
> `[Subscribe to Basic ₱290]` `[Subscribe to Pro ₱690]`

- Style: warm amber/yellow (not red/error) — data loss anxiety should be explicitly defused ("your data is safe")
- Non-blocking — user can still navigate to dashboard, products, transactions, reports (read-only, per RLS confirmed earlier)
- Reappears on next app open if still unsubscribed; doesn't nag mid-session beyond the persistent banner

### Blocked-action handling
Rather than letting a write attempt hit the DB trigger and surface a raw exception, **pre-empt in the UI**:
- Disable/gray out: "Add Product", "Edit Product", "New Sale"/checkout button, "Add Staff", AI assistant entry point
- On tap of a disabled action (if not fully hidden), show a toast: *"This feature requires an active subscription. Subscribe to continue."* — friendlier than the DB's raw `"Store is read-only"` message
- Still catch the DB exception as a fallback (belt-and-suspenders, in case UI state gets out of sync with server state)

### Screens to touch
- [ ] `home_shell.dart` — banner injection point
- [ ] Register/checkout screen — disable "complete sale"
- [ ] Inventory panel — disable add/edit product
- [ ] Admin > Users — disable add staff
- [ ] AI assistant entry point — disable, route to subscribe screen instead
- [ ] New `SubscribeScreen` — shows both tiers with feature comparison (reuse the pricing table content), routes into Play Billing flow (Part 3)

---

## Part 3 — Google Play Billing Integration

### Goal
Let a read-only store owner actually subscribe from inside the app, turning `plan` + `plan_expires_at` into something billing-driven rather than manually edited in Supabase.

### Package
`in_app_purchase` (official Flutter plugin, wraps Google Play Billing on Android). Given KahaPro is Android/iOS via one Flutter codebase but distribution model is Google Play first, start Android-only; revisit App Store billing separately if/when iOS distribution happens.

### Play Console setup (manual, one-time)
- [ ] Create two subscription products in Play Console: `kahapro_basic_monthly` (₱290), `kahapro_pro_monthly` (₱690)
- [ ] Configure grace period / account hold behavior (Play handles retry on failed renewal automatically — decide if that should map to a grace period before flipping to read-only, or if `plan_expires_at` should flip immediately)
- [ ] Set up a service account for server-side receipt verification (Google Play Developer API)

### Client-side flow
1. `SubscribeScreen` lists both tiers, user taps one
2. `InAppPurchase.instance.buyNonConsumable(...)` (subscriptions are non-consumable) launches Play's native purchase sheet
3. On purchase stream update (`purchaseDetails.status == PurchaseStatus.purchased`), send the purchase token to a new Supabase Edge Function for **server-side verification** — never trust the client-reported purchase state alone
4. Edge Function verifies the token against Google Play Developer API, and only then updates `stores.plan` and `stores.plan_expires_at`
5. Client calls `InAppPurchase.instance.completePurchase(purchaseDetails)` once server confirms

### New Edge Function: `verify-play-purchase`
- Input: `purchaseToken`, `productId`, `storeId`
- Calls Google Play Developer API (`purchases.subscriptions.get`) to confirm the purchase is valid and active
- On success: updates `stores.plan` (`basic`/`pro`) and `stores.plan_expires_at` (subscription expiry from Google's response, or `null` if you want active-paid plans to never read as "expired" until a renewal actually fails)
- Should also run on a recurring schedule (Supabase cron / pg_cron) to re-check active subscriptions and catch cancellations/lapses Google reports asynchronously — not just at purchase time

### Open decisions
- [ ] Renewal handling: does `plan_expires_at` get set to the actual Play-reported renewal date, or does an active paid subscription just stay `null` (never read-only) until a cancellation/failure is detected?
- [ ] Downgrade path: if a `pro` subscriber lets it lapse, do they fall to read-only immediately or get a grace period like the original trial?
- [ ] Annual plans — mentioned earlier as a "2-months-free" idea but not finalized; decide before wiring Play Console products, since each billing period needs its own product ID
- [ ] Refund/cancellation webhook handling (Google Play Real-time Developer Notifications) — needed eventually so a refunded purchase doesn't leave a store permanently on `pro`

### Testing checklist
- [ ] License-test account purchase → confirm `plan` and `plan_expires_at` update correctly
- [ ] Cancel subscription in Play Console test tools → confirm store eventually flips back to read-only
- [ ] Confirm a store mid-purchase (payment processing) isn't incorrectly shown as read-only during the brief window before server verification completes

---

## Summary of what's already done vs. what this doc covers

| Layer | Status |
|---|---|
| `plans` table, tier limits | ✅ Done |
| `ai_credit_allotment()` reading from `plans` | ✅ Done |
| `store_is_read_only()` + write-blocking triggers | ✅ Done, tested |
| `consume_ai_credit()` respecting read-only | ✅ Done |
| RLS confirmed read-only-safe (reads unaffected) | ✅ Confirmed |
| 6-provider AI fallback (Groq → Mistral → Cerebras → OpenRouter → Gemini → Premium) | 📋 This doc, Part 1 |
| Trial-expired banner + disabled actions (Flutter) | 📋 This doc, Part 2 |
| Google Play Billing wiring | 📋 This doc, Part 3 |
