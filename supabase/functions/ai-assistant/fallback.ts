import { callGroq } from './providers/groq.ts';
import { callMistral } from './providers/mistral.ts';
import { callGemini } from './providers/gemini.ts';
import { callDeepSeek } from './providers/deepseek.ts';
import { callOpenRouter } from './providers/openrouter.ts';
import { callOpenAI } from './providers/openai.ts';

export type ProviderResult = { text: string; provider: string };

const providers = [
  { name: 'groq', fn: callGroq },
  { name: 'mistral', fn: callMistral },
  { name: 'gemini', fn: callGemini },
  { name: 'deepseek', fn: callDeepSeek },
  { name: 'openrouter', fn: callOpenRouter },
  { name: 'openai', fn: callOpenAI }, // paid — only reached if all 5 earlier tiers fail
];

export async function callWithFallback(prompt: string): Promise<ProviderResult> {
  let lastError: unknown;

  for (const { name, fn } of providers) {
    try {
      const text = await fn(prompt);
      if (name === 'openai') {
        console.warn('[ai-assistant] fell through to PAID OpenAI — check free-tier usage/limits');
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

function isRetryable(err: unknown): boolean {
  const status = (err as any)?.status;
  return status === 429 || (status >= 500 && status < 600) || (err as any)?.name === 'TimeoutError';
}