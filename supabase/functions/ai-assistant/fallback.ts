import { callGroq } from './providers/groq.ts';
import { callMistral } from './providers/mistral.ts';
import { callGemini } from './providers/gemini.ts';
import { callOpenRouter } from './providers/openrouter.ts';
import { callDeepSeek } from './providers/deepseek.ts';
import { callOpenAI } from './providers/openai.ts';

export type ProviderResult = { text: string; provider: string };

// Order: free tiers first (Groq, Mistral, Gemini, OpenRouter), then paid
// fallbacks (DeepSeek, OpenAI) last — DeepSeek and OpenAI both require a
// prepaid account balance (no free tier), so they're only reached if all
// four free-tier providers are down.
const providers = [
  { name: 'groq', fn: callGroq },
  { name: 'mistral', fn: callMistral },
  { name: 'gemini', fn: callGemini },
  { name: 'openrouter', fn: callOpenRouter },
  { name: 'deepseek', fn: callDeepSeek }, // paid — only reached if all 4 free tiers fail
  { name: 'openai', fn: callOpenAI },     // paid — only reached if all 5 earlier tiers fail
];

export async function callWithFallback(prompt: string): Promise<ProviderResult> {
  let lastError: unknown;

  for (const { name, fn } of providers) {
    try {
      const text = await fn(prompt);
      if (name === 'deepseek' || name === 'openai') {
        console.warn(`[ai-assistant] fell through to PAID provider (${name}) — check usage/limits`);
      }
      return { text, provider: name };
    } catch (err) {
      lastError = err;
      console.error(`[ai-assistant] ${name} failed:`, err);
      if (!isRetryable(err)) throw err;
    }
  }

  throw new Error(`All AI providers failed. Last error: ${lastError}`);
}

// Determines whether a provider failure should trigger fallback to the next
// provider, vs. being treated as fatal (aborts the whole chain immediately).
//
// Retryable (try next provider): the failure came from the provider's HTTP
// API — any HTTP error status (401, 403, 404, 429, 5xx, etc.) is specific to
// THIS provider (bad/expired key, wrong model name, rate limit, outage) and
// says nothing about whether other providers would also fail. We used to
// allow-list specific statuses here (429/401/403/5xx) but kept discovering
// more real-world cases that weren't covered (e.g. a 404 from a wrong model
// name) — so now any numeric HTTP status is treated as retryable.
//
// Fatal (abort immediately, don't try other providers): the failure has NO
// status at all — meaning it happened before we got any HTTP response, e.g.
// a bug in our own request-building code. That would fail identically
// against every provider, so trying the rest is pointless and just delays
// surfacing the real bug.
function isRetryable(err: unknown): boolean {
  const status = (err as any)?.status;
  return typeof status === 'number';
}
