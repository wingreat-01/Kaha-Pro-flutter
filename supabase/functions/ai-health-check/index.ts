// supabase/functions/ai-health-check/index.ts
//
// Diagnostic-only endpoint. Calls all 6 providers directly and in
// parallel with a trivial prompt, independent of fallback.ts's chain
// logic — so a dead provider here doesn't affect the real
// ai-assistant function, doesn't touch credits, and doesn't write to
// ai_usage_log. Deploy separately and hit it whenever you want a
// quick "who's up right now" snapshot.

import { callGroq } from '../ai-assistant/providers/groq.ts';
import { callMistral } from '../ai-assistant/providers/mistral.ts';
import { callGemini } from '../ai-assistant/providers/gemini.ts';
import { callOpenRouter } from '../ai-assistant/providers/openrouter.ts';
import { callDeepSeek } from '../ai-assistant/providers/deepseek.ts';
import { callOpenAI } from '../ai-assistant/providers/openai.ts';
import type { ChatMessage, ProviderFn } from '../ai-assistant/types.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS, GET',
};

const PROVIDERS: { name: string; fn: ProviderFn }[] = [
  { name: 'groq', fn: callGroq },
  { name: 'openrouter', fn: callOpenRouter },
  { name: 'mistral', fn: callMistral },
  { name: 'deepseek', fn: callDeepSeek },
  { name: 'openai', fn: callOpenAI },
  { name: 'gemini', fn: callGemini },
];

const PING_MESSAGES: ChatMessage[] = [
  { role: 'user', content: 'Reply with exactly one word: OK' },
];

// 20s timeout: generous enough that a genuinely slow (but working)
// provider -- e.g. Gemini in a reasoning/thinking mode -- doesn't get
// misreported as "down" just because it took 11-12s. A provider that
// still doesn't answer within 20s is a real problem either way.
const TIMEOUT_MS = 20_000;

// Anything answering slower than this still counts as "up", but gets
// flagged as "up (slow)" in the result so a trend (e.g. Gemini
// creeping past 5-8s on every run) is visible without misreading it
// as an outage.
const SLOW_THRESHOLD_MS = 5_000;

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(`timed out after ${ms}ms`)), ms),
    ),
  ]);
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const startedAt = Date.now();

  const results = await Promise.all(
    PROVIDERS.map(async ({ name, fn }) => {
      const t0 = Date.now();
      try {
        await withTimeout(fn(PING_MESSAGES, []), TIMEOUT_MS);
        const ms = Date.now() - t0;
        return { provider: name, status: ms > SLOW_THRESHOLD_MS ? 'up (slow)' : 'up', ms };
      } catch (err) {
        const status = (err as any)?.status ?? null;
        return {
          provider: name,
          status: 'down',
          ms: Date.now() - t0,
          http_status: status,
          error: err instanceof Error ? err.message : String(err),
        };
      }
    }),
  );

  return new Response(
    JSON.stringify({ checked_at: new Date().toISOString(), total_ms: Date.now() - startedAt, results }, null, 2),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
});

// --- Manual testing ---
//
// curl -s 'https://<project-ref>.supabase.co/functions/v1/ai-health-check' \
//   -H "Authorization: Bearer <anon or service key>" | jq
//
// Or straight from DevTools console (F12) on any page, no auth needed
// if you set verify_jwt = false for this function in config.toml:
//
// fetch('https://<project-ref>.supabase.co/functions/v1/ai-health-check')
//   .then(r => r.json())
//   .then(d => console.table(d.results));
