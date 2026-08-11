# Kahapro Subscription Plan

Kahapro's subscription/paid-tier plan (Free/Basic/Pro), AI assistant gating, backup strategy, and build progress — separate track from the core Kahapro Flutter app work.

- Goal: paid tier exists so the AI admin assistant has a sustainable cost model; everything else in Kahapro (POS, inventory, offline queue, transactions) stays free at every tier
- Plans sketched: Free ₱0, Basic ₱290/mo (₱2,900/yr), Pro ₱690/mo (₱6,900/yr) — staff account limits (2/5/unlimited), transaction history retention (30/90/unlimited days), AI credits (0/10/30 per month), total product cap (5/30/unlimited, all categories combined), and emailed cloud sync (none/monthly/weekly) are the gated features; priority support Pro-only
- Product cap is deliberately tight on Free (5 products) as the main conversion lever — target is for most real stores to land on Basic rather than stay on Free long-term, since a real sari-sari/food-cart store typically carries more than 5 SKUs
- Decision: launching free-only for now — paid tier/gating is a future option, not built yet; all stores on Free tier, AI assistant runs ungated on the provider fallback chain with no credit enforcement live
- Enforcement design (for when gating is turned on): server-side only, in the AI Edge Function via a `consume_ai_credit()` Postgres RPC (row-locked, lazy monthly reset) — the Flutter app hiding buttons is UX only, not the real gate, since anyone could hit the Edge Function URL directly with a valid JWT
- Backup strategy decided: server-side DIY backup (GitHub Actions daily cron → `pg_dump` → Cloudflare R2, free) is the real safety net, independent of client-facing features; Supabase Pro ($25/mo, adds daily backups + PITR) is the planned upgrade once real customer sales data is on the line, not tied to hitting free-tier storage/row limits
- Decided against relying on client local-storage as a backup — doesn't protect against the actual failure modes (server-side bugs, migrations, Supabase incidents), and target market (sari-sari stores) skews non-technical/unlikely to back up manually
- Export Data feature planned: client-facing CSV/Excel download of transactions/inventory/summaries, available at every tier (transparency + personal safety net, not a substitute for the server-side backup)
- Import Data feature planned but scoped down: v1 = products/inventory import only (low risk); transaction/sales-history import deferred to v2 because transactions are immutable and ledger-numbered (`assign_transaction_number` trigger + `store_counters`) — a naive bulk import would collide with or fake that sequence, so imported rows need a `source = 'imported'` tag kept separate from live POS-recorded transactions
- Emailed cloud sync planned as a paid convenience (reuses the Export engine + a delivery cron + email provider like Resend/Postmark), gated Basic=monthly/Pro=weekly, same gating pattern as AI credits
- Build order: (1) `stores.plan` column + `current_store_plan()` helper — in progress, migration `001_add_stores_plan.sql` written (additive only, defaults everyone to 'free', no app-facing change yet); (2) build the AI assistant Edge Function with the plan/credit check built in from the start; (3) Flutter-side fetch plan + hide/lock AI entry point; (4) Google Play Billing integration + manual plan-flip path for support/testing

## AI Assistant Edge Function

Build split into 4 pieces: (1) credit-tracking schema + `consume_ai_credit()` RPC, (2) Edge Function skeleton (auth + credit gate, no real AI calls), (3) provider fallback logic, (4) Flutter chat UI — **pieces 1–3 done and deployed to production; piece 4 (Flutter chat UI) not started.**

Open decision flagged: whether a provider failure after a credit is consumed should refund it (currently does not).

**Provider fallback order:** Groq → Mistral → Gemini → OpenRouter → DeepSeek → OpenAI. DeepSeek and OpenAI are both fully paid/prepaid-balance providers (no free tier — confirmed by testing, both currently return errors due to $0 account balance) so they sit last as paid-only fallbacks, after the four genuinely free providers.

`has_ai_credit()` function run and confirmed live in production; `ai-assistant` Edge Function deployed and validated end-to-end against prod on the pro test store (`fc34caa5-2b3a-400f-b94e-1e44fa96ba66`, BiryaniKing) and a 0-credit free-tier store (`a34a01f0-0437-4071-b906-01508d3bdb30`): credit deduction confirmed exact (27→26 on success), 403 with no deduction confirmed on 0-credit store.

### Full provider-by-provider live test results

| Provider | Status | Notes |
|---|---|---|
| Groq | ✅ | Direct call confirmed working |
| Mistral | ✅ | Fallback confirmed |
| Gemini | ✅ | Fallback confirmed, after fixing a deprecated-model bug |
| OpenRouter | ✅ | Fallback confirmed; uses model `openrouter/free` — OpenRouter's built-in random router across ~18 free-variant models, avoiding catalog-drift/deprecation risk |
| DeepSeek | ❌ | Blocked on 402 — account has $0 balance; DeepSeek has no free tier at all, needs prepaid top-up |
| OpenAI | ❌ | Blocked on 429/`insufficient_quota` — account has $0 credit balance, needs top-up at platform.openai.com billing |

### Bugs found and fixed this round

1. **`fallback.ts` — `isRetryable()` gate too narrow (found twice).** This function decides whether a provider failure falls through to the next provider or aborts the whole chain. First it only treated 429/5xx/timeout as fallthrough-worthy, so a 401 (invalid/expired key) wrongly aborted the chain instead of trying the next provider. Then a 404 (from the Gemini deprecated-model bug below) also fell outside the allow-list and hit the same failure mode. Fixed by replacing the status-code allow-list entirely with "any numeric HTTP status is retryable" — only a status-less error (meaning our own request never reached the network) is treated as fatal. Reverified live via a broken-Groq+Mistral test that correctly fell through to Gemini.

2. **`gemini.ts` — deprecated pinned model.** The pinned model `gemini-2.5-flash` returned 404 "no longer available to new users" for a freshly-created Gemini API key/project. Switched to the rolling alias `gemini-flash-latest` (currently resolves to `gemini-3.6-flash` per its `modelVersion` field) so it won't go stale the same way again. Confirmed working live.

3. **Red herring, not a bug:** Gemini API keys created from Google AI Studio in mid-2026 onward use a new `AQ.` prefix format (~53 chars) instead of the legacy `AIzaSy...` format (39 chars) — this is expected/current, not a wrong key. It looked suspicious during debugging before the real cause (deprecated model name) was found.
