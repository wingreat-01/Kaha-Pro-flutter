import { callGroq } from './providers/groq.ts';
import { callMistral } from './providers/mistral.ts';
import { callGemini } from './providers/gemini.ts';
import { callOpenRouter } from './providers/openrouter.ts';
import { callDeepSeek } from './providers/deepseek.ts';
import { callOpenAI } from './providers/openai.ts';
import type { ChatMessage, ProviderFn, ProviderResponse, ToolDef } from './types.ts';

export type FallbackResult = { response: ProviderResponse; provider: string; fn: ProviderFn };

// Order: free tiers first (Groq, OpenRouter, Mistral, DeepSeek, OpenAI),
// then Gemini last — Gemini is the only provider on a paid (prepaid
// balance) tier here, so it's only reached if all five free-tier
// providers above it fail.
const providers: { name: string; fn: ProviderFn }[] = [
  { name: 'groq', fn: callGroq },
  { name: 'openrouter', fn: callOpenRouter },
  { name: 'mistral', fn: callMistral },
  { name: 'deepseek', fn: callDeepSeek },
  { name: 'openai', fn: callOpenAI },
  { name: 'gemini', fn: callGemini }, // paid — only reached if all 5 free tiers above fail
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

  for (const { name, fn } of providers) {
    try {
      const response = await fn(messages, tools);
      if (name === 'gemini') {
        console.warn(`[ai-assistant] fell through to PAID provider (${name}) — check usage/limits`);
      }
      return { response, provider: name, fn };
    } catch (err) {
      lastError = err;
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
