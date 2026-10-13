// Client for the local Briefing service (Briefing/briefing.py). Same endpoints and
// the same tolerant decoding as App/Dayflow/Views/UI/Briefing/BriefingService.swift.

export interface Todo {
  id: string;
  text: string;
  done: boolean;
  source?: string;
}

export interface TimelineCard {
  key: string;
  startTs: number;
  endTs?: number;
  title?: string;
  summary?: string;
  category?: string;
  type: string;
}

export interface Stats {
  totalMinutes: number;
  bestHours: number[];
  byCategory: Record<string, number>;
}

export interface BriefingState {
  briefing: string;
  briefingAt?: number;
  sessionGoal?: string;
  timeline: TimelineCard[];
  todos: Todo[];
  stats: Stats;
  writer: string;
}

export class ApiError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json => typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const num = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) ? v : undefined);

async function request<T>(path: string, init?: RequestInit, timeoutMs = 15_000): Promise<T> {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(path, { ...init, signal: controller.signal });
    if (!res.ok) throw new ApiError(res.status, `Briefing service answered ${res.status}`);
    return (await res.json()) as T;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new ApiError(0, "The Briefing service took too long to answer.");
    }
    throw new ApiError(0, "Can't reach the Briefing service.");
  } finally {
    window.clearTimeout(timer);
  }
}

const post = <T>(path: string, body: Json, timeoutMs?: number) =>
  request<T>(
    path,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) },
    timeoutMs,
  );

function decodeTodo(v: unknown): Todo | null {
  if (!isObject(v)) return null;
  const id = str(v.id);
  const text = str(v.text);
  if (!id || !text) return null;
  return { id, text, done: v.done === true, source: str(v.source) };
}

function decodeCard(v: unknown, index: number): TimelineCard | null {
  if (!isObject(v)) return null;
  // Cards have start_ts/end_ts; notes only have ts (see BriefingCard in Swift).
  const start = num(v.start_ts) ?? num(v.ts);
  if (start === undefined) return null;
  return {
    key: `${start}-${num(v.ln) ?? index}`,
    startTs: start,
    endTs: num(v.end_ts),
    title: str(v.title),
    summary: str(v.summary),
    category: str(v.category),
    type: str(v.type) ?? "card",
  };
}

function decodeStats(v: unknown): Stats {
  const s = isObject(v) ? v : {};
  const byCategory: Record<string, number> = {};
  if (isObject(s.by_category)) {
    for (const [k, value] of Object.entries(s.by_category)) {
      const n = num(value);
      if (n !== undefined) byCategory[k] = n;
    }
  }
  return {
    totalMinutes: num(s.total_minutes) ?? 0,
    bestHours: Array.isArray(s.best_hours) ? s.best_hours.filter((h): h is number => typeof h === "number") : [],
    byCategory,
  };
}

const compact = <T>(items: (T | null)[]): T[] => items.filter((x): x is T => x !== null);

export function decodeState(raw: unknown): BriefingState {
  const r = isObject(raw) ? raw : {};
  const settings = isObject(r.settings) ? r.settings : {};
  return {
    briefing: str(r.briefing) ?? "",
    briefingAt: num(r.briefing_at),
    sessionGoal: str(r.session_goal) || undefined,
    timeline: Array.isArray(r.timeline) ? compact(r.timeline.map(decodeCard)) : [],
    todos: Array.isArray(r.todos) ? compact(r.todos.map(decodeTodo)) : [],
    stats: decodeStats(r.stats),
    writer: str(settings.llm_backend) ?? "ollama",
  };
}

export const api = {
  state: async () => decodeState(await request<unknown>("/api/state")),
  // Writing a briefing runs the model; the app allows it up to 5 minutes.
  newBriefing: () => post<{ briefing?: string }>("/api/brief", {}, 300_000),
  addTodo: (text: string) => post<{ todos?: unknown[] }>("/api/todo", { add: text }),
  setTodo: (id: string, done: boolean) => post<{ todos?: unknown[] }>("/api/todo", { id, done }),
  feedback: (up: boolean) => post<{ ok?: boolean }>("/api/brief/feedback", { rating: up ? "up" : "down" }),
  resume: () => post<{ opened?: string[] }>("/api/resume", { confirm: true }, 30_000),
  setWriter: (backend: string) => post<Json>("/api/settings", { llm_backend: backend }),
  // Searches memory and the timeline (citations like [2026-10-12#3]). /api/answer is the
  // on-screen companion and answers from screen text, so it is not used here.
  ask: async (question: string) => {
    const res = await post<{ answer?: unknown }>("/api/ask", { q: question }, 300_000);
    return str(res.answer) ?? "";
  },
};
