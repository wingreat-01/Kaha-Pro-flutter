// supabase/functions/ai-assistant/providers/openrouter.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callOpenRouter(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://openrouter.ai/api/v1/chat/completions',
      apiKeyEnvVar: 'OPENROUTER_API_KEY',
      // NOTE: switched from 'openrouter/free' to a named tool-calling-capable
      // free model -- the random free-tier router doesn't reliably support
      // function calling across whatever it lands on. Verify this model is
      // still free/available on OpenRouter before deploying.
      model: 'meta-llama/llama-3.3-70b-instruct:free',
      extraHeaders: { 'HTTP-Referer': 'https://kahapro.app', 'X-Title': 'KahaPro' },
      providerLabel: 'OpenRouter',
    },
    messages,
    tools,
  );
}
