// supabase/functions/ai-assistant/index.ts
//
// Piece 2 of 4 (see kahapro-subscription-plan.md "Build progress").
// This piece is deliberately incomplete: the auth + credit-gating
// path is real and testable end-to-end, but callWithFallback() below
// is a stub that returns a placeholder instead of spending a real
// Gemini/Groq/Mistral call. That's piece 3 — kept separate so the
// security boundary (the credit gate) can be built and tested without
// any AI provider cost while it's being wired up.

import { createClient } from 'jsr:@supabase/supabase-js@2';

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

// Placeholder for piece 3. Signature is final — prompt in, string
// response out — so swapping this for the real Gemini → Groq →
// Mistral fallback chain later doesn't touch anything below.
async function callWithFallback(prompt: string): Promise<string> {
  return `[stub response — AI provider not wired up yet] You said: ${prompt}`;
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
    // token costs are visible in piece 3.
    return jsonResponse({ error: 'prompt is too long.' }, 400);
  }

  // 1. Try to consume one credit under the caller's own RLS-scoped
  //    session. This single RPC call handles the free-tier check (0
  //    credits, always false), the monthly reset, and the decrement,
  //    all in one row-locked transaction — see consume_ai_credit() in
  //    003_add_ai_credits.sql.
  const { data: creditGranted, error: creditError } = await supabase.rpc('consume_ai_credit');

  if (creditError) {
    console.error('consume_ai_credit RPC failed:', creditError);
    return jsonResponse({ error: 'Could not verify AI access.' }, 500);
  }

  // 2. Gate BEFORE calling any AI provider — this is the actual
  //    security boundary, not the Flutter UI. A Free-tier store
  //    always has 0 credits (ai_credit_allotment('free') = 0), so
  //    this single check covers both "wrong tier" and "used up this
  //    month's credits" without a separate plan lookup.
  if (!creditGranted) {
    return jsonResponse(
      { error: 'No AI credits remaining this month. Upgrade or wait for next cycle.' },
      403,
    );
  }

  // 3. Only now, spend a real API call (stubbed until piece 3).
  try {
    const aiResponse = await callWithFallback(prompt);
    return jsonResponse({ response: aiResponse }, 200);
  } catch (err) {
    // Credit is already spent at this point — see the "Open decisions"
    // note added below about whether a provider-side failure here
    // should refund the credit.
    console.error('callWithFallback failed:', err);
    return jsonResponse({ error: 'AI assistant is temporarily unavailable.' }, 502);
  }
});

// --- Manual testing (once deployed) ---
//
// curl -i -X POST 'https://<project-ref>.supabase.co/functions/v1/ai-assistant' \
//   -H "Authorization: Bearer <a real user access token>" \
//   -H "Content-Type: application/json" \
//   -d '{"prompt": "hello"}'
//
// Expected on a Free-tier test store: 403, "No AI credits remaining...".
// Flip the store to basic/pro first (see 001_add_stores_plan.sql's
// manual override) to get a 200 with the stub response instead, and
// confirm stores.ai_credits_remaining actually decremented.
