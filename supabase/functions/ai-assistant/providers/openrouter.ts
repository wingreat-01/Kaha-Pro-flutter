// supabase/functions/ai-assistant/providers/openrouter.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callOpenRouter(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://openrouter.ai/api/v1/chat/completions',
      apiKeyEnvVar: 'OPENROUTER_API_KEY',
      // Switched from OpenAI's gpt-oss-20b free-tier model to Google's
      // Gemma 4 26B A4B free-tier model -- lower usage volume on
      // OpenRouter (less shared-capacity congestion) and native
      // function-calling support for our TOOL_DEFS. Verify this model
      // is still free/available on OpenRouter before deploying.
      model: 'google/gemma-4-26b-a4b-it:free',
      extraHeaders: { 'HTTP-Referer': 'https://kahapro.app', 'X-Title': 'MERQ' },
      providerLabel: 'OpenRouter',
    },
    messages,
    tools,
  );
}
