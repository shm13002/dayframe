// The models Jarvis can think with, as Hermes names them. Grok is the fast default; Qwen on
// Ollama is the offline fallback (its 4K context is too small for Hermes's tools, so answers
// from it are marked "limited").
export interface Brain {
  id: "grok" | "chatgpt" | "claude" | "qwen";
  label: string;
  /** Hermes provider ids that belong to this brain. */
  providers: readonly string[];
  limited: boolean;
}

export const BRAINS: readonly Brain[] = [
  { id: "grok", label: "Grok", providers: ["xai", "xai-oauth", "grok"], limited: false },
  { id: "chatgpt", label: "ChatGPT", providers: ["openai-codex", "codex", "openai"], limited: false },
  { id: "claude", label: "Claude", providers: ["anthropic", "claude", "claude-code"], limited: false },
  { id: "qwen", label: "Qwen (offline)", providers: ["ollama", "custom", "local"], limited: true },
];

/** Which brain a Hermes provider/model pair is. Unknown providers show their own name. */
export function brainFor(provider: string | null | undefined, model?: string | null): Brain | null {
  const p = (provider ?? "").toLowerCase();
  const m = (model ?? "").toLowerCase();
  if (m.startsWith("qwen")) return BRAINS[3] ?? null;
  return BRAINS.find((brain) => brain.providers.some((id) => p === id || p.startsWith(id + ":"))) ?? null;
}
