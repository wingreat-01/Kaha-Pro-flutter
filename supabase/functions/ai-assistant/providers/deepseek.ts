// supabase/functions/ai-assistant/providers/deepseek.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callDeepSeek(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://api.deepseek.com/chat/completions',
      apiKeyEnvVar: 'DEEPSEEK_API_KEY',
      model: 'deepseek-v4-flash',
      providerLabel: 'DeepSeek',
    },
    messages,
    tools,
  );
}
