// supabase/functions/ai-assistant/providers/openrouter.ts
import type { ChatMessage, ProviderResponse, ToolDef } from '../types.ts';
import { callOpenAICompatible } from './openai_compatible.ts';

export function callOpenRouter(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  return callOpenAICompatible(
    {
      url: 'https://openrouter.ai/api/v1/chat/completions',
      apiKeyEnvVar: 'OPENROUTER_API_KEY',
      // Switched from the free-tier Gemma 4 26B A4B model to the PAID
      // gpt-oss-20b variant ($0.02/M input, $0.10/M output) after the
      // free-tier daily quota (20/day unverified, 1000/day with any
      // credit balance) was tripping 429s on this provider. At an
      // estimated ~$0.0003/turn (see ai_usage_log cost analysis), the
      // $10 credit balance covers ~30k+ turns -- cost is not the
      // constraint here, quota reliability was. No ":free" suffix --
      // this is billed per-token against the OpenRouter balance.
      model: 'openai/gpt-oss-20b',
      extraHeaders: { 'HTTP-Referer': 'https://kahapro.app', 'X-Title': 'MERQ' },
      providerLabel: 'OpenRouter',
    },
    messages,
    tools,
  );
}
