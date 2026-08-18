// supabase/functions/ai-assistant/providers/openai_compatible.ts
//
// One shared implementation for every provider that speaks the
// OpenAI chat/completions + tools wire format: OpenAI, Groq, Mistral,
// DeepSeek, OpenRouter. Each of those files becomes a ~10-line
// wrapper that just supplies its own URL/key/model/headers.

import type { ChatMessage, ProviderResponse, ToolCall, ToolDef } from '../types.ts';

export interface OpenAICompatibleConfig {
  url: string;
  apiKeyEnvVar: string;
  model: string;
  extraHeaders?: Record<string, string>;
  providerLabel: string; // for error messages, e.g. "Groq"
}

function toOpenAIMessages(messages: ChatMessage[]): unknown[] {
  return messages.map((m) => {
    if (m.role === 'assistant') {
      return {
        role: 'assistant',
        content: m.content,
        ...(m.tool_calls?.length
          ? {
              tool_calls: m.tool_calls.map((tc) => ({
                id: tc.id,
                type: 'function',
                function: { name: tc.name, arguments: JSON.stringify(tc.arguments) },
              })),
            }
          : {}),
      };
    }
    if (m.role === 'tool') {
      return { role: 'tool', tool_call_id: m.tool_call_id, content: m.content };
    }
    return { role: m.role, content: m.content };
  });
}

function toOpenAITools(tools: ToolDef[]): unknown[] {
  return tools.map((t) => ({
    type: 'function',
    function: { name: t.name, description: t.description, parameters: t.parameters },
  }));
}

export async function callOpenAICompatible(
  config: OpenAICompatibleConfig,
  messages: ChatMessage[],
  tools: ToolDef[],
): Promise<ProviderResponse> {
  const apiKey = Deno.env.get(config.apiKeyEnvVar);
  if (!apiKey) throw new Error(`${config.apiKeyEnvVar} not set`);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000); // slightly longer: tool round-trips take more time

  try {
    const res = await fetch(config.url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        ...(config.extraHeaders ?? {}),
      },
      body: JSON.stringify({
        model: config.model,
        messages: toOpenAIMessages(messages),
        tools: tools.length ? toOpenAITools(tools) : undefined,
        max_tokens: 800,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const err: any = new Error(`${config.providerLabel} error ${res.status}`);
      err.status = res.status;
      throw err;
    }

    const data = await res.json();
    const msg = data?.choices?.[0]?.message;
    if (!msg) throw new Error(`${config.providerLabel} returned no message`);

    if (msg.tool_calls?.length) {
      const calls: ToolCall[] = msg.tool_calls.map((tc: any) => ({
        id: tc.id,
        name: tc.function.name,
        arguments: JSON.parse(tc.function.arguments || '{}'),
      }));
      return { type: 'tool_calls', calls };
    }

    if (!msg.content) throw new Error(`${config.providerLabel} returned empty response`);
    return { type: 'text', text: msg.content };
  } finally {
    clearTimeout(timeout);
  }
}
