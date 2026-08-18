// supabase/functions/ai-assistant/providers/groq.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callGroq(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://api.groq.com/openai/v1/chat/completions',
      apiKeyEnvVar: 'GROQ_API_KEY',
      model: 'openai/gpt-oss-120b',
      providerLabel: 'Groq',
    },
    messages,
    tools,
  );
}
