// Jarvis's conversation state: one gateway event in, the next state out.
// Ported from Herald OS apps/desktop/src/lib/chat-model.ts (MIT, Luke The Dev), trimmed to what
// the Jarvis tab shows, and extended with `brain` (which model answered).
import type {
  GatewayEvent,
  MessageCompletePayload,
  SessionLiveInfo,
  StreamDeltaPayload,
  ToolCompletePayload,
  ToolStartPayload,
  TranscriptMessage,
  TurnStatus,
} from "./hermes/upstream/gateway-events";

export interface UserMessage {
  id: string;
  role: "user";
  text: string;
  ts: number;
}

export interface AssistantMessage {
  id: string;
  role: "assistant";
  text: string;
  reasoning: string;
  streaming: boolean;
  status?: TurnStatus;
  error?: string;
  ts: number;
}

export interface ToolMessage {
  id: string;
  role: "tool";
  toolId: string;
  name: string;
  args?: Record<string, unknown> | null;
  context?: string | null;
  resultText?: string | null;
  summary?: string | null;
  durationS?: number | null;
  running: boolean;
  ts: number;
}

export interface SystemMessage {
  id: string;
  role: "system";
  text: string;
  level: "info" | "warn" | "error";
  ts: number;
}

export type ChatMessage = UserMessage | AssistantMessage | ToolMessage | SystemMessage;

export interface ChatState {
  sessionId: string;
  title: string;
  messages: ChatMessage[];
  streaming: boolean;
  status?: { kind: string; text: string };
  info: SessionLiveInfo;
  /** The assistant bubble currently receiving deltas. */
  openAssistantId: string | null;
}

let counter = 0;
export const nextId = (prefix = "m"): string => `${prefix}${Date.now().toString(36)}${(counter++).toString(36)}`;

export function emptyChat(sessionId: string, info: SessionLiveInfo = {}): ChatState {
  return {
    sessionId,
    title: info.title ?? "",
    messages: [],
    streaming: Boolean(info.running),
    info,
    openAssistantId: null,
  };
}

const textOf = (value: unknown): string =>
  typeof value === "string" ? value : value == null ? "" : JSON.stringify(value);

/** The gateway's stored transcript rows, as Jarvis messages. */
export function fromTranscript(rows: readonly TranscriptMessage[]): ChatMessage[] {
  const out: ChatMessage[] = [];
  for (const row of rows) {
    if (row.display_kind === "hidden") continue;
    const ts = row.timestamp ? (row.timestamp < 1e12 ? row.timestamp * 1000 : row.timestamp) : Date.now();
    if (row.role === "user") {
      out.push({ id: nextId("u"), role: "user", text: textOf(row.text), ts });
    } else if (row.role === "assistant") {
      const text = textOf(row.text);
      if (text || row.reasoning) {
        out.push({
          id: nextId("a"),
          role: "assistant",
          text,
          reasoning: row.reasoning ?? "",
          streaming: false,
          status: "complete",
          ts,
        });
      }
    } else if (row.role === "tool") {
      out.push({
        id: nextId("t"),
        role: "tool",
        toolId: String(row.tool_call_id ?? row.row_id ?? nextId("tc")),
        name: row.name ?? "tool",
        args: row.args ?? null,
        context: row.context ?? null,
        resultText: textOf(row.text) || null,
        running: false,
        ts,
      });
    } else if (row.role === "system" && row.text) {
      out.push({ id: nextId("s"), role: "system", text: textOf(row.text), level: "info", ts });
    }
  }
  return out;
}

function replaceMessage(state: ChatState, next: ChatMessage): ChatState {
  return { ...state, messages: state.messages.map((m) => (m.id === next.id ? next : m)) };
}

function openAssistant(state: ChatState): { state: ChatState; message: AssistantMessage } {
  const existing = state.messages.find(
    (m): m is AssistantMessage => m.id === state.openAssistantId && m.role === "assistant",
  );
  if (existing) return { state, message: existing };
  const message: AssistantMessage = {
    id: nextId("a"),
    role: "assistant",
    text: "",
    reasoning: "",
    streaming: true,
    ts: Date.now(),
  };
  return {
    state: { ...state, openAssistantId: message.id, streaming: true, messages: [...state.messages, message] },
    message,
  };
}

export function appendUser(state: ChatState, text: string): ChatState {
  return {
    ...state,
    streaming: true,
    status: undefined,
    openAssistantId: null,
    messages: [...state.messages, { id: nextId("u"), role: "user", text, ts: Date.now() }],
  };
}

export function appendSystem(state: ChatState, text: string, level: SystemMessage["level"] = "info"): ChatState {
  return { ...state, messages: [...state.messages, { id: nextId("s"), role: "system", text, level, ts: Date.now() }] };
}

function onDelta(state: ChatState, payload: StreamDeltaPayload | undefined, field: "text" | "reasoning"): ChatState {
  if (!payload?.text) return state;
  const opened = openAssistant(state);
  const message = { ...opened.message, [field]: opened.message[field] + payload.text, streaming: true };
  return replaceMessage({ ...opened.state, streaming: true }, message);
}

function onToolStart(state: ChatState, payload: ToolStartPayload | undefined): ChatState {
  if (!payload) return state;
  const existing = state.messages.find((m): m is ToolMessage => m.role === "tool" && m.toolId === payload.tool_id);
  if (existing) {
    return replaceMessage(state, {
      ...existing,
      args: payload.args ?? existing.args,
      context: payload.context ?? existing.context,
      running: true,
    });
  }
  // Text before a tool call stays in the bubble above the tool row; later text opens a new bubble.
  const open = state.messages.find((m): m is AssistantMessage => m.id === state.openAssistantId);
  const sealed = open ? replaceMessage(state, { ...open, streaming: false }) : state;
  return {
    ...sealed,
    streaming: true,
    openAssistantId: null,
    messages: [
      ...sealed.messages,
      {
        id: nextId("t"),
        role: "tool",
        toolId: payload.tool_id,
        name: payload.name,
        args: payload.args ?? null,
        context: payload.context ?? payload.preview ?? null,
        running: true,
        ts: Date.now(),
      },
    ],
  };
}

function onToolComplete(state: ChatState, payload: ToolCompletePayload | undefined): ChatState {
  if (!payload) return state;
  const existing = state.messages.find((m): m is ToolMessage => m.role === "tool" && m.toolId === payload.tool_id);
  const patch = {
    resultText: payload.result_text ?? (typeof payload.result === "string" ? payload.result : null),
    summary: payload.summary ?? null,
    durationS: payload.duration_s ?? null,
    running: false,
  };
  if (existing) return replaceMessage(state, { ...existing, ...patch });
  return {
    ...state,
    messages: [
      ...state.messages,
      {
        id: nextId("t"),
        role: "tool",
        toolId: payload.tool_id,
        name: payload.name,
        args: payload.args ?? null,
        ts: Date.now(),
        ...patch,
      },
    ],
  };
}

function onComplete(state: ChatState, payload: MessageCompletePayload | undefined): ChatState {
  const finalText = typeof payload?.text === "string" ? payload.text : "";
  const status = payload?.status ?? "complete";
  let next = state;
  const open = state.messages.find((m): m is AssistantMessage => m.id === state.openAssistantId);
  if (open) {
    next = replaceMessage(state, {
      ...open,
      // The final payload wins when the stream was partial or empty.
      text: finalText && (payload?.partial || !open.text) ? finalText : open.text || finalText,
      reasoning: open.reasoning || payload?.reasoning || "",
      streaming: false,
      status,
      error: payload?.error ?? undefined,
    });
  } else if (finalText) {
    next = {
      ...state,
      messages: [
        ...state.messages,
        {
          id: nextId("a"),
          role: "assistant",
          text: finalText,
          reasoning: payload?.reasoning ?? "",
          streaming: false,
          status,
          ts: Date.now(),
        },
      ],
    };
  }
  if (status === "error" && payload?.error && !finalText) next = appendSystem(next, payload.error, "error");
  return {
    ...next,
    streaming: false,
    openAssistantId: null,
    status: undefined,
    messages: next.messages.map((m) => (m.role === "tool" && m.running ? { ...m, running: false } : m)),
  };
}

/** Pure reducer. Unknown events change nothing. */
export function reduceChatEvent(state: ChatState, event: GatewayEvent): ChatState {
  switch (event.type) {
    case "message.start":
      return { ...state, streaming: true };
    case "message.delta":
      return onDelta(state, event.payload as StreamDeltaPayload, "text");
    case "reasoning.delta":
      return onDelta(state, event.payload as StreamDeltaPayload, "reasoning");
    case "thinking.delta": {
      const text = (event.payload as StreamDeltaPayload | undefined)?.text ?? "";
      return text.trim()
        ? { ...state, status: { kind: "thinking", text: text.replace(/^[^\p{L}\p{N}]+/u, "").trim() || text } }
        : { ...state, status: undefined };
    }
    case "message.interim": {
      const payload = event.payload as { text: string; already_streamed: boolean } | undefined;
      if (!payload || payload.already_streamed || !payload.text) return { ...state, openAssistantId: null };
      return {
        ...state,
        openAssistantId: null,
        messages: [
          ...state.messages,
          {
            id: nextId("a"),
            role: "assistant",
            text: payload.text,
            reasoning: "",
            streaming: false,
            status: "complete",
            ts: Date.now(),
          },
        ],
      };
    }
    case "tool.start":
      return onToolStart(state, event.payload as ToolStartPayload);
    case "tool.complete":
      return onToolComplete(state, event.payload as ToolCompletePayload);
    case "message.complete":
      return onComplete(state, event.payload as MessageCompletePayload);
    case "status.update": {
      const payload = event.payload as { kind: string; text: string } | undefined;
      return payload ? { ...state, status: payload } : state;
    }
    case "session.title": {
      const payload = event.payload as { title: string } | undefined;
      return payload ? { ...state, title: payload.title, info: { ...state.info, title: payload.title } } : state;
    }
    case "session.info": {
      const info = (event.payload ?? {}) as SessionLiveInfo;
      return { ...state, info: { ...state.info, ...info }, title: info.title ?? state.title };
    }
    case "error": {
      const payload = event.payload as { message: string } | undefined;
      return payload
        ? { ...appendSystem(state, payload.message, "error"), streaming: false, openAssistantId: null }
        : state;
    }
    default:
      return state;
  }
}

/** The text of the newest finished answer, for the voice. */
export function lastAnswer(state: ChatState): string {
  for (let i = state.messages.length - 1; i >= 0; i--) {
    const m = state.messages[i];
    if (m?.role === "user") return "";
    if (m?.role === "assistant" && !m.streaming && m.text) return m.text;
  }
  return "";
}
