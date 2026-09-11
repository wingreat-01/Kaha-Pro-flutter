import { callGroq } from './providers/groq.ts';
import { callMistral } from './providers/mistral.ts';
import { callGemini } from './providers/gemini.ts';
import { callOpenRouter } from './providers/openrouter.ts';
import { callDeepSeek } from './providers/deepseek.ts';
import { callOpenAI } from './providers/openai.ts';
import type { ChatMessage, ProviderFn, ProviderResponse, ToolDef } from './types.ts';

export type FallbackResult = { response: ProviderResponse; provider: string; fn: ProviderFn };

// Order: free tiers first (Groq, Mistral, DeepSeek, OpenAI), then the
// two paid (prepaid balance) providers -- OpenRouter (openai/gpt-oss-20b,
// switched off the free Gemma 4 model after free-tier 429s), then
// Gemini last. Retry order is unaffected by a provider's tier; this
// just documents which ones now draw down a paid balance.
const providers: { name: string; fn: ProviderFn }[] = [
  { name: 'groq', fn: callGroq },
  { name: 'openrouter', fn: callOpenRouter }, // paid — see providers/openrouter.ts
  { name: 'mistral', fn: callMistral },
  { name: 'deepseek', fn: callDeepSeek },
  { name: 'openai', fn: callOpenAI },
  { name: 'gemini', fn: callGemini }, // paid
];

// Only used to pick the provider for the FIRST call of a turn. Once one
// succeeds, index.ts keeps calling that same provider's fn directly for
// any further tool-result round-trips in the same turn — switching
// providers mid-loop would break tool_call id / message threading.
export async function callWithFallback(
  messages: ChatMessage[],
  tools: ToolDef[],
): Promise<FallbackResult> {
  let lastError: unknown;
  let failuresBeforeThis = 0;

  for (const { name, fn } of providers) {
    try {
      const response = await fn(messages, tools);
      const isPaid = name === 'gemini' || name === 'openrouter';
      if (isPaid && failuresBeforeThis > 0) {
        // A real fallback: one or more providers ahead of this one in
        // the list just failed, and we landed on a paid one as a
        // result -- worth a warn, since repeated occurrences mean
        // spend is being driven by upstream outages, not by design.
        console.warn(
          `[ai-assistant] fell through ${failuresBeforeThis} failed provider(s) to reach paid provider (${name}) — check usage/limits`,
        );
      } else if (isPaid) {
        // Normal path: this paid provider was simply next in line and
        // nothing failed ahead of it (e.g. OpenRouter at position 2).
        // Informational only -- not a fallback event, so not a warn.
        console.log(`[ai-assistant] resolved via paid provider (${name})`);
      }
      return { response, provider: name, fn };
    } catch (err) {
      lastError = err;
      failuresBeforeThis++;
      console.error(`[ai-assistant] ${name} failed:`, err);
      if (!isRetryable(err)) throw err;
    }
  }

  throw new Error(`All AI providers failed. Last error: ${lastError}`);
}

// Retryable (try next provider): any numeric HTTP status — specific to
// THIS provider (bad/expired key, wrong model, rate limit, outage, wrong
// model name) and says nothing about whether other providers would fail.
// Fatal (abort immediately): no status at all, meaning the failure
// happened before any HTTP response — a bug in our own request-building
// code that would fail identically against every provider.
function isRetryable(err: unknown): boolean {
  const status = (err as any)?.status;
  return typeof status === 'number';
}
