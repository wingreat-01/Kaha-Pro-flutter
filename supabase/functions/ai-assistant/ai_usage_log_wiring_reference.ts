// Reference only -- I haven't seen your actual index.ts/fallback.ts,
// so this shows the SHAPE of the change (what to add and exactly
// where), not a drop-in replacement. Splice this into wherever your
// fallback chain currently calls consume_ai_credit() after a
// provider succeeds.

const PAID_PROVIDERS = new Set(["deepseek", "openai"]);

// ...inside the fallback loop, once a provider has actually
// succeeded (this should sit right next to -- not instead of --
// your existing consume_ai_credit() call, since that call is what
// actually gates billing; this insert is purely for visibility and
// should never be allowed to block or fail the response):

await consume_ai_credit(storeId); // existing call, unchanged

try {
  await supabaseAdmin.from("ai_usage_log").insert({
    store_id: storeId,
    provider: successfulProviderName, // e.g. "groq", "mistral", "deepseek"
    is_paid_tier: PAID_PROVIDERS.has(successfulProviderName),
  });
} catch (logErr) {
  // Deliberately swallowed -- this is a metrics side-channel, not
  // part of the request's success path. A failed insert here should
  // never turn a successful AI reply into a failed one, and isRetryable()
  // should never see this error at all.
  console.error("ai_usage_log insert failed (non-fatal):", logErr);
}

// Once this has been live for a few weeks, a query like:
//
//   select provider, count(*), 
//          round(100.0 * count(*) filter (where is_paid_tier) / count(*), 1) as pct_paid
//   from ai_usage_log
//   where created_at > now() - interval '30 days'
//   group by provider;
//
// gives the real fallback-hit-rate number that was missing when the
// 30/90 credit decision was made on judgment instead of data.
