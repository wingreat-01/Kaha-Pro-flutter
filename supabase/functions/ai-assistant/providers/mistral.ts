// supabase/functions/ai-assistant/providers/mistral.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callMistral(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://api.mistral.ai/v1/chat/completions',
      apiKeyEnvVar: 'MISTRAL_API_KEY',
      model: 'mistral-small-latest',
      providerLabel: 'Mistral',
    },
    messages,
    tools,
  );
}
