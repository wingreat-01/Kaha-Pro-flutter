// supabase/functions/ai-assistant/providers/openai.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callOpenAI(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://api.openai.com/v1/chat/completions',
      apiKeyEnvVar: 'OPENAI_API_KEY',
      model: 'gpt-5.4-nano',
      providerLabel: 'OpenAI',
    },
    messages,
    tools,
  );
}
