// supabase/functions/ai-assistant/providers/openrouter.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callOpenRouter(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://openrouter.ai/api/v1/chat/completions',
      apiKeyEnvVar: 'OPENROUTER_API_KEY',
      // Switched from Llama 3.3 70B to OpenAI's gpt-oss-20b free-tier
      // model -- verify this model is still free/available on
      // OpenRouter before deploying.
      model: 'openai/gpt-oss-20b:free',
      extraHeaders: { 'HTTP-Referer': 'https://kahapro.app', 'X-Title': 'MERQ' },
      providerLabel: 'OpenRouter',
    },
    messages,
    tools,
  );
}
