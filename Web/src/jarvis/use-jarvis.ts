// One connection to Hermes for the Jarvis tab: sessions, the open conversation, approval
// requests and the brains this Mac is signed in to.
import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import { BRAINS, type Brain, brainFor } from "./brains";
import { appendSystem, appendUser, emptyChat, fromTranscript, reduceChatEvent, type ChatState } from "./chat-model";
import type { JarvisContext } from "./host";
import { postToHost } from "./host";
import { VOICE_CONTEXT, firstSpokenSentence } from "./spoken";
import type {
  ApprovalRequestParams,
  ClarifyRequestParams,
  GatewayEvent,
  ModelOptionsResult,
  SessionCreateResult,
  SessionListResult,
  SessionListRow,
  SessionResumeResult,
} from "./hermes/upstream/gateway-events";
import { type ConnectionState, JsonRpcGatewayClient } from "./hermes/upstream/json-rpc-gateway";
import type { ServerRequest } from "./hermes/upstream/json-rpc-channel";

/** Herald's bridge plugin only serves sessions from this source; keep it. */
const SOURCE = "herald_os";

export type Pending =
  | { kind: "approval"; request: ServerRequest; params: ApprovalRequestParams }
  | { kind: "clarify"; request: ServerRequest; params: ClarifyRequestParams };

export interface BrainOption extends Brain {
  provider: string;
  model: string;
}

type Action =
  | { type: "reset"; chat: ChatState | null }
  | { type: "event"; event: GatewayEvent }
  | { type: "user"; text: string }
  | { type: "system"; text: string; level: "info" | "warn" | "error" };

function chatReducer(state: ChatState | null, action: Action): ChatState | null {
  if (action.type === "reset") return action.chat;
  if (!state) return state;
  if (action.type === "user") return appendUser(state, action.text);
  if (action.type === "system") return appendSystem(state, action.text, action.level);
  if (action.event.session_id && action.event.session_id !== state.sessionId) return state;
  return reduceChatEvent(state, action.event);
}

/** The model a provider row offers by default. */
function modelOf(row: ModelOptionsResult["providers"][number], current: ModelOptionsResult): string {
  if (current.provider === row.slug && current.model) return current.model;
  return row.featured_models?.[0] ?? row.models?.[0] ?? "";
}

export function useJarvis(context: JarvisContext) {
  const clientRef = useRef<JsonRpcGatewayClient | null>(null);
  const [connection, setConnection] = useState<ConnectionState>("idle");
  const [chat, dispatch] = useReducer(chatReducer, null);
  const [sessions, setSessions] = useState<SessionListRow[]>([]);
  const [pending, setPending] = useState<Pending[]>([]);
  const [brains, setBrains] = useState<BrainOption[]>([]);
  const [brainId, setBrainId] = useState<Brain["id"]>(context.brain);
  const chatRef = useRef(chat);
  chatRef.current = chat;
  const surfaceRef = useRef<"voice" | "chat">("chat");

  const request = useCallback(<T>(method: string, params: Record<string, unknown> = {}) => {
    const client = clientRef.current;
    if (!client) return Promise.reject(new Error("Jarvis isn't connected to Hermes yet."));
    return client.request<T>(method, params);
  }, []);

  const refreshSessions = useCallback(async () => {
    try {
      const result = await request<SessionListResult>("session.list", { limit: 40 });
      setSessions(result.sessions ?? []);
    } catch {
      /* the list is a convenience; the conversation still works */
    }
  }, [request]);

  const refreshBrains = useCallback(async () => {
    try {
      const options = await request<ModelOptionsResult>("model.options", {});
      const found: BrainOption[] = [];
      for (const brain of BRAINS) {
        const row = options.providers.find(
          (p) => p.authenticated !== false && brainFor(p.slug, modelOf(p, options))?.id === brain.id,
        );
        if (row) found.push({ ...brain, provider: row.slug, model: modelOf(row, options) });
      }
      setBrains(found);
    } catch {
      setBrains([]);
    }
  }, [request]);

  // Connect whenever Swift hands over a backend.
  useEffect(() => {
    if (!context.port || !context.token) return;
    const client = new JsonRpcGatewayClient({ requestIdPrefix: "jarvis", requestTimeoutMs: 180_000 });
    clientRef.current = client;
    const offState = client.onState(setConnection);
    const offEvent = client.onEvent((event) => {
      dispatch({ type: "event", event });
      if (event.type === "message.complete" && event.session_id === chatRef.current?.sessionId) {
        postToHost({ type: "busy", busy: false });
        void refreshSessions();
      }
      if (event.type === "message.start") postToHost({ type: "busy", busy: true });
    });
    const offRequest = client.onRequest((req) => {
      if (req.method === "approval") {
        setPending((list) => [
          ...list,
          { kind: "approval", request: req, params: req.params as unknown as ApprovalRequestParams },
        ]);
        return true;
      }
      if (req.method === "clarify") {
        setPending((list) => [
          ...list,
          { kind: "clarify", request: req, params: req.params as unknown as ClarifyRequestParams },
        ]);
        return true;
      }
      return false;
    });
    const offCancel = client.on("request.cancel" as never, (event: GatewayEvent) => {
      const id = (event.payload as { request_id?: string } | undefined)?.request_id;
      if (id) setPending((list) => list.filter((p) => p.request.id !== id));
    });
    client
      .connect(`ws://127.0.0.1:${context.port}/api/ws?token=${encodeURIComponent(context.token)}`)
      .then(() => Promise.all([refreshSessions(), refreshBrains()]))
      .catch(() => setConnection("error"));
    return () => {
      offState();
      offEvent();
      offRequest();
      offCancel();
      client.close();
      clientRef.current = null;
    };
  }, [context.port, context.token, refreshSessions, refreshBrains]);

  useEffect(() => setBrainId(context.brain), [context.brain]);

  // After a voice turn, speak the reply's first sentence (asked to be a summary through
  // voice_context) as soon as it has streamed in, while the rest keeps arriving on screen.
  const spokenTurnRef = useRef<string | null>(null);
  useEffect(() => {
    if (!chat || surfaceRef.current !== "voice") return;
    const lastUser = chat.messages.findLast((m) => m.role === "user");
    if (!lastUser || spokenTurnRef.current === lastUser.id) return;
    const start = chat.messages.indexOf(lastUser);
    const reply = chat.messages.slice(start + 1).find((m) => m.role === "assistant" && m.text);
    if (!reply || reply.role !== "assistant") return;
    const line = firstSpokenSentence(reply.text, !reply.streaming);
    if (!line) return;
    spokenTurnRef.current = lastUser.id;
    postToHost({ type: "speak", text: line });
  }, [chat]);

  /** The brain to use: the chosen one if signed in, else the first that is (Qwen last). */
  const activeBrain = useMemo(
    () => brains.find((b) => b.id === brainId) ?? brains.find((b) => !b.limited) ?? brains[0] ?? null,
    [brains, brainId],
  );

  const newChat = useCallback(() => {
    dispatch({ type: "reset", chat: null });
    setPending([]);
  }, []);

  const openSession = useCallback(
    async (id: string) => {
      try {
        const result = await request<SessionResumeResult>("session.resume", { session_id: id, source: SOURCE });
        const next = emptyChat(result.session_id, result.info);
        dispatch({ type: "reset", chat: { ...next, messages: fromTranscript(result.messages ?? []) } });
      } catch (error) {
        dispatch({ type: "reset", chat: emptyChat("", {}) });
        dispatch({
          type: "system",
          text: `Couldn't open that conversation: ${(error as Error).message}`,
          level: "error",
        });
      }
    },
    [request],
  );

  const send = useCallback(
    async (text: string, surface: "voice" | "chat" = "chat") => {
      const trimmed = text.trim();
      if (!trimmed) return;
      surfaceRef.current = surface;
      if (surface === "chat") postToHost({ type: "stopSpeaking" });
      let current = chatRef.current;
      try {
        if (!current?.sessionId) {
          const created = await request<SessionCreateResult>("session.create", {
            source: SOURCE,
            title: trimmed.slice(0, 60),
            ...(activeBrain ? { provider: activeBrain.provider, model: activeBrain.model } : {}),
          });
          current = emptyChat(created.session_id, created.info);
          dispatch({ type: "reset", chat: current });
        }
        dispatch({ type: "user", text: trimmed });
        postToHost({ type: "busy", busy: true });
        await request("prompt.submit", {
          session_id: current.sessionId,
          text: trimmed,
          surface: surface === "voice" ? "voice-live" : "chat",
          ...(surface === "voice" ? { voice_context: VOICE_CONTEXT, voice_turn: true } : {}),
        });
      } catch (error) {
        postToHost({ type: "busy", busy: false });
        if (!chatRef.current) dispatch({ type: "reset", chat: emptyChat("", {}) });
        dispatch({ type: "system", text: (error as Error).message, level: "error" });
      }
    },
    [request, activeBrain],
  );

  const stop = useCallback(async () => {
    postToHost({ type: "stopSpeaking" });
    const id = chatRef.current?.sessionId;
    if (id) await request("session.interrupt", { session_id: id }).catch(() => undefined);
  }, [request]);

  const answer = useCallback((item: Pending, result: Record<string, unknown>) => {
    item.request.respond(result);
    setPending((list) => list.filter((p) => p.request.id !== item.request.id));
  }, []);

  return {
    connection,
    chat,
    sessions,
    pending,
    brains,
    activeBrain,
    chooseBrain: setBrainId,
    newChat,
    openSession,
    send,
    stop,
    answer,
  };
}

export type Jarvis = ReturnType<typeof useJarvis>;
