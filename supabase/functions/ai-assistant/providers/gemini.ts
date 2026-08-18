// supabase/functions/ai-assistant/providers/gemini.ts
//
// Gemini's function-calling format differs from the OpenAI-style
// providers: no `system` role (uses systemInstruction), no tool_call
// ids (matched by name instead), and function results are sent back
// as a 'function' role part rather than a 'tool' role message. This
// file does its own mapping rather than sharing openai_compatible.ts.

import type { ChatMessage, ProviderResponse, ToolCall, ToolDef } from '../types.ts';

function toGeminiContents(messages: ChatMessage[]): unknown[] {
  const contents: unknown[] = [];
  for (const m of messages) {
    if (m.role === 'system') continue; // handled separately via systemInstruction
    if (m.role === 'user') {
      contents.push({ role: 'user', parts: [{ text: m.content }] });
    } else if (m.role === 'assistant') {
      if (m.tool_calls?.length) {
        contents.push({
          role: 'model',
          parts: m.tool_calls.map((tc) => ({
            functionCall: { name: tc.name, args: tc.arguments },
          })),
        });
      } else {
        contents.push({ role: 'model', parts: [{ text: m.content ?? '' }] });
      }
    } else if (m.role === 'tool') {
      contents.push({
        role: 'function',
        parts: [{ functionResponse: { name: m.name, response: { content: m.content } } }],
      });
    }
  }
  return contents;
}

function toGeminiTools(tools: ToolDef[]): unknown[] {
  if (!tools.length) return [];
  return [
    {
      functionDeclarations: tools.map((t) => ({
        name: t.name,
        description: t.description,
        parameters: t.parameters,
      })),
    },
  ];
}

export async function callGemini(messages: ChatMessage[], tools: ToolDef[]): Promise<ProviderResponse> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) throw new Error('GEMINI_API_KEY not set');

  const systemMsg = messages.find((m) => m.role === 'system');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000);

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...(systemMsg ? { systemInstruction: { parts: [{ text: systemMsg.content }] } } : {}),
          contents: toGeminiContents(messages),
          tools: toGeminiTools(tools).length ? toGeminiTools(tools) : undefined,
        }),
        signal: controller.signal,
      },
    );

    if (!res.ok) {
      const err: any = new Error(`Gemini error ${res.status}`);
      err.status = res.status;
      throw err;
    }

    const data = await res.json();
    const parts = data?.candidates?.[0]?.content?.parts ?? [];

    const functionCalls = parts.filter((p: any) => p.functionCall);
    if (functionCalls.length) {
      const calls: ToolCall[] = functionCalls.map((p: any, i: number) => ({
        id: `call_${i}`, // Gemini has no call id; synthetic, matched back by name in index.ts
        name: p.functionCall.name,
        arguments: p.functionCall.args ?? {},
      }));
      return { type: 'tool_calls', calls };
    }

    const text = parts.map((p: any) => p.text).filter(Boolean).join('');
    if (!text) throw new Error('Gemini returned empty response');
    return { type: 'text', text };
  } finally {
    clearTimeout(timeout);
  }
}
