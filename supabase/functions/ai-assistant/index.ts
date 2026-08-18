// supabase/functions/ai-assistant/index.ts
//
// Now runs a real tool-calling loop instead of a single flat-prompt
// round-trip. Credit is still checked before and consumed after —
// but now "after" means after the whole turn (which may include
// several tool round-trips), not after a single provider call. A
// turn that uses 4 tool calls under the hood still costs 1 credit.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { callWithFallback } from './fallback.ts';
import { SYSTEM_PROMPT } from './system-prompt.ts';
import { TOOL_DEFS, executeTool } from './tools.ts';
import type { ChatMessage } from './types.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MAX_TOOL_ITERATIONS = 6; // guard against a runaway tool-call loop

const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function fmtDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// Computes weekday name + Monday-Sunday boundaries for "this week" and
// "last week" in code, rather than leaving the model to derive day-of-
// week and do date arithmetic from a bare ISO date itself -- LLMs are
// unreliable at that and will confidently produce the wrong Monday.
function dateContext(todayIso: string): string {
  const today = new Date(`${todayIso}T00:00:00Z`);
  const dayOfWeek = today.getUTCDay(); // 0 = Sunday .. 6 = Saturday
  const weekdayName = WEEKDAY_NAMES[dayOfWeek];

  const diffToMonday = (dayOfWeek + 6) % 7; // days since most recent Monday
  const thisMonday = new Date(today);
  thisMonday.setUTCDate(today.getUTCDate() - diffToMonday);
  const thisSunday = new Date(thisMonday);
  thisSunday.setUTCDate(thisMonday.getUTCDate() + 6);

  const lastMonday = new Date(thisMonday);
  lastMonday.setUTCDate(thisMonday.getUTCDate() - 7);
  const lastSunday = new Date(thisMonday);
  lastSunday.setUTCDate(thisMonday.getUTCDate() - 1);

  return [
    `Today's date: ${todayIso} (${weekdayName}).`,
    `"This week" = ${fmtDate(thisMonday)} to ${fmtDate(thisSunday)} (Mon-Sun).`,
    `"Last week" = ${fmtDate(lastMonday)} to ${fmtDate(lastSunday)} (Mon-Sun).`,
    `Use these exact date ranges for get_sales/get_best_sellers/compare_sales when the user says "this week" or "last week" -- do not recalculate them yourself.`,
  ].join(' ');
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
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

  // Caller's own JWT — RLS on products/ingredients/transactions/etc.
  // scopes every tool query to this user's store automatically.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  // Body now carries `messages`: the recent conversation, including
  // any assistant tool_calls / tool-result messages from earlier in
  // the same turn window (e.g. a withdraw_inventory confirmation
  // round-trip) so the model can see its own prior tool-call
  // arguments (item_id, quantity, ...) rather than having to guess
  // them from flattened text on the next turn. The client is never
  // trusted to send a 'system' role or arbitrary extra keys -- only
  // the fields ChatMessage actually uses are copied over.
  let userMessages: ChatMessage[];
  try {
    const body = await req.json();
    if (!Array.isArray(body.messages) || body.messages.length === 0) {
      return jsonResponse({ error: 'messages array is required.' }, 400);
    }
    userMessages = body.messages.map((m: any) => {
      if (m.role !== 'user' && m.role !== 'assistant' && m.role !== 'tool') {
        throw new Error(`invalid role in messages: ${m.role}`);
      }
      const msg: ChatMessage = { role: m.role, content: m.content ?? null };
      if (Array.isArray(m.tool_calls)) msg.tool_calls = m.tool_calls;
      if (typeof m.tool_call_id === 'string') msg.tool_call_id = m.tool_call_id;
      if (typeof m.name === 'string') msg.name = m.name;
      return msg;
    });
  } catch (e) {
    const msg = e instanceof Error && e.message.startsWith('invalid role') ? e.message : 'Invalid JSON body.';
    return jsonResponse({ error: msg }, 400);
  }

  const totalChars = userMessages.reduce((n, m) => n + (m.content?.length ?? 0), 0);
  if (totalChars > 8000) {
    return jsonResponse({ error: 'Conversation is too long for this request.' }, 400);
  }

  // 1. Pure credit check — no spend yet.
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

  const today = new Date().toISOString().slice(0, 10);
  const messages: ChatMessage[] = [
    { role: 'system', content: `${SYSTEM_PROMPT}\n\n${dateContext(today)}` },
    ...userMessages,
  ];

  // Everything appended from here on (tool_calls, tool results, and
  // the final assistant reply) is new this turn and gets handed back
  // to the client to persist and resend verbatim next time -- the
  // client's own messages (everything up to this point) don't need
  // to be echoed back, it already has them.
  const turnStartIdx = messages.length;

  let providerUsed: string;
  let finalText: string;

  try {
    // First call goes through the fallback chain; once a provider
    // succeeds, stick with it for the rest of this turn's tool loop.
    const first = await callWithFallback(messages, TOOL_DEFS);
    providerUsed = first.provider;
    let response = first.response;
    let callFn = first.fn;

    let iterations = 0;
    while (response.type === 'tool_calls') {
      if (++iterations > MAX_TOOL_ITERATIONS) {
        throw new Error('Tool-call loop exceeded max iterations.');
      }

      messages.push({ role: 'assistant', content: null, tool_calls: response.calls });

      for (const call of response.calls) {
        const result = await executeTool(supabase, call.name, call.arguments);
        messages.push({
          role: 'tool',
          tool_call_id: call.id,
          name: call.name,
          content: JSON.stringify(result),
        });
      }

      try {
        response = await callFn(messages, TOOL_DEFS);
      } catch (midLoopErr) {
        // The provider that succeeded on turn 1 can still fail on a
        // later round-trip (e.g. rate-limited after our earlier calls
        // this minute) -- calling callFn directly here bypasses
        // fallback.ts's retry chain entirely, so without this catch
        // one rate-limited follow-up call kills the whole turn even
        // though four other free providers are still available.
        // Re-running callWithFallback re-selects from the top of the
        // provider list with the accumulated messages/tool results
        // intact, so this is the same recovery the first call gets.
        console.warn(`[ai-assistant] mid-loop call on ${providerUsed} failed, retrying via fallback chain:`, midLoopErr);
        const retry = await callWithFallback(messages, TOOL_DEFS);
        providerUsed = retry.provider;
        response = retry.response;
        callFn = retry.fn;
      }
    }

    finalText = response.text;
    // Add the final reply to the same array so it's included in the
    // turn_messages slice below -- the client needs it in the
    // structured history too, not just in the `response` field, so a
    // later turn's window includes it in the right place relative to
    // any tool_calls/tool messages that preceded it.
    messages.push({ role: 'assistant', content: finalText });
  } catch (err) {
    console.error('AI turn failed, no credit deducted:', err);
    return jsonResponse({ error: 'AI assistant is temporarily unavailable.' }, 502);
  }

  const turnMessages = messages.slice(turnStartIdx);

  // 2. Only now, having a real final answer, spend the credit —
  // whole turn, regardless of how many tool round-trips it took.
  const { error: consumeError } = await supabase.rpc('consume_ai_credit');
  if (consumeError) {
    console.error('consume_ai_credit RPC failed after successful AI response:', consumeError);
  }

  // Read back the real remaining count and hand it to the client
  // directly, rather than letting Flutter guess "minus 1" locally.
  // The local optimistic decrement can drift from the truth (e.g. a
  // credit gets consumed here but the client throws before reaching
  // its own decrement step) -- returning the authoritative number
  // every response means the UI can never show a stale/wrong count.
  let creditsRemaining: number | null = null;
  const { data: storeRow, error: creditReadError } = await supabase
    .from('stores')
    .select('ai_credits_remaining')
    .single();
  if (creditReadError) {
    console.error('Could not read back ai_credits_remaining:', creditReadError);
  } else {
    creditsRemaining = storeRow?.ai_credits_remaining ?? null;
  }

  return jsonResponse(
    {
      response: finalText,
      provider: providerUsed,
      credits_remaining: creditsRemaining,
      // Structured messages generated this turn (assistant tool_calls,
      // tool results, final assistant text) -- the client appends these
      // to its persisted history and resends them verbatim on the next
      // request, instead of flattening to plain text and losing tool
      // call arguments like item_id along the way.
      turn_messages: turnMessages,
    },
    200,
  );
});

// --- Manual testing (once deployed) ---
//
// curl -i -X POST 'https://<project-ref>.supabase.co/functions/v1/ai-assistant' \
//   -H "Authorization: Bearer <a real user access token>" \
//   -H "Content-Type: application/json" \
//   -d '{"messages": [{"role": "user", "content": "how much stock do we have left of our best seller?"}]}'
