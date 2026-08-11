// supabase/functions/ai-assistant/index.ts
//
// Piece 3 of 4 (see kahapro-subscription-plan.md "Build progress").
// Credit gating is now split into two steps instead of one:
// has_ai_credit() is a pure check (no row lock, no update) called
// BEFORE attempting any provider, and consume_ai_credit() is called
// AFTER a provider actually succeeds. This means a request that
// fails across all 6 providers costs the store nothing — see
// kahapro-ai-fallback-and-billing-plan.md Part 1 for the full
// rationale and the known race-window tradeoff of splitting the
// check and the deduct into two calls.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { callWithFallback } from './fallback.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  // CORS preflight — needed since the Flutter web build calls this
  // cross-origin from the app's own domain.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed.' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'Missing Authorization header.' }, 401);
  }

  // Caller's own JWT, not a service-role key — RLS on `stores` does
  // the same store-scoping it already does everywhere else in the
  // app. No new trust boundary to design or reason about.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  // Parse + validate the request body before touching credits — a
  // malformed request shouldn't cost the store anything.
  let prompt: string;
  try {
    const body = await req.json();
    prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }
  if (prompt.length === 0) {
    return jsonResponse({ error: 'prompt is required.' }, 400);
  }
  if (prompt.length > 4000) {
    // Arbitrary generous cap — real limit tuning happens once actual
    // token costs are visible across the 6-provider chain.
    return jsonResponse({ error: 'prompt is too long.' }, 400);
  }

  // 1. Pure check — no row lock, no update. Confirms the store has
  //    credit available this cycle without spending anything yet.
  //    Free/trial-lapsed stores always resolve to 0 via
  //    ai_credit_allotment(), so this single check covers both
  //    "wrong tier" and "used up this month's credits."
  const { data: hasCredit, error: creditCheckError } = await supabase.rpc('has_ai_credit');

  if (creditCheckError) {
    console.error('has_ai_credit RPC failed:', creditCheckError);
    return jsonResponse({ error: 'Could not verify AI access.' }, 500);
  }

  if (!hasCredit) {
    return jsonResponse(
      { error: 'No AI credits remaining this month. Upgrade or wait for next cycle.' },
      403,
    );
  }

  // 2. Attempt the real 6-provider fallback chain. Nothing is spent
  //    yet — this is intentional (see file header comment).
  let aiResponse: string;
  let providerUsed: string;
  try {
    const result = await callWithFallback(prompt);
    aiResponse = result.text;
    providerUsed = result.provider;
  } catch (err) {
    console.error('callWithFallback failed, no credit deducted:', err);
    return jsonResponse({ error: 'AI assistant is temporarily unavailable.' }, 502);
  }

  // 3. Only now, having actually gotten a usable response, spend the
  //    credit. This RPC still does the monthly-reset + decrement in
  //    one row-locked transaction — see consume_ai_credit() in
  //    003_add_ai_credits.sql. It's unchanged from piece 2; only the
  //    point in the flow where it's called has moved.
  const { error: consumeError } = await supabase.rpc('consume_ai_credit');
  if (consumeError) {
    // The AI call already succeeded and the user already has their
    // answer — log this loudly but still return the response rather
    // than making the user eat the failure of an accounting step
    // that isn't their fault.
    console.error('consume_ai_credit RPC failed after successful AI response:', consumeError);
  }

  return jsonResponse({ response: aiResponse, provider: providerUsed }, 200);
});

// --- Manual testing (once deployed) ---
//
// curl -i -X POST 'https://<project-ref>.supabase.co/functions/v1/ai-assistant' \
//   -H "Authorization: Bearer <a real user access token>" \
//   -H "Content-Type: application/json" \
//   -d '{"prompt": "hello"}'
//
// Expected on a read-only/expired-credit test store: 403.
// Expected on a store with credit: 200, real AI response +
// "provider" field showing which of the 6 actually served it, and
// stores.ai_credits_remaining decremented by exactly 1.