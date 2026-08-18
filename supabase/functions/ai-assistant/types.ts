// supabase/functions/ai-assistant/types.ts
//
// Shared shapes for the tool-calling loop. Every provider adapter
// converts these into its own wire format and converts its response
// back into ProviderResponse -- index.ts and fallback.ts never see
// provider-specific shapes.

export type ChatMessage =
  | { role: 'system'; content: string }
  | { role: 'user'; content: string }
  | { role: 'assistant'; content: string | null; tool_calls?: ToolCall[] }
  | { role: 'tool'; tool_call_id: string; name: string; content: string };

export interface ToolCall {
  id: string; // synthetic for providers (Gemini) that don't emit one
  name: string;
  arguments: Record<string, unknown>;
}

// JSON-schema tool definition, provider-agnostic (OpenAI-style shape;
// every adapter maps this to what its API actually expects).
export interface ToolDef {
  name: string;
  description: string;
  parameters: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: string[];
  };
}

export type ProviderResponse =
  | { type: 'text'; text: string }
  | { type: 'tool_calls'; calls: ToolCall[] };

export type ProviderFn = (
  messages: ChatMessage[],
  tools: ToolDef[],
) => Promise<ProviderResponse>;
