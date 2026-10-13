import { useCallback, useEffect, useRef, useState } from "react";
import { api, ApiError, type BriefingState } from "./api";

export type Phase = "loading" | "ready" | "offline";

const REFRESH_MS = 120_000;

const message = (error: unknown) => (error instanceof ApiError ? error.message : "Something went wrong.");

/** Briefing data plus every action the screen can take. Mirrors BriefingService.swift. */
export function useBriefing() {
  const [state, setState] = useState<BriefingState | null>(null);
  const [phase, setPhase] = useState<Phase>("loading");
  const [error, setError] = useState<string | null>(null);
  const [writing, setWriting] = useState(false);
  const [asking, setAsking] = useState(false);
  const [answer, setAnswer] = useState<string | null>(null);
  // Bumps every time a new briefing text arrives, so the hero can replay its reveal.
  const [briefingVersion, setBriefingVersion] = useState(0);
  const lastBriefing = useRef<string | null>(null);
  const hasState = useRef(false);

  const refresh = useCallback(async () => {
    try {
      const next = await api.state();
      hasState.current = true;
      setState(next);
      setPhase("ready");
      if (next.briefing !== lastBriefing.current) {
        lastBriefing.current = next.briefing;
        setBriefingVersion((v) => v + 1);
      }
    } catch (e) {
      if (!hasState.current) setPhase("offline");
      else setError(message(e));
    }
  }, []);

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), REFRESH_MS);
    const onFocus = () => void refresh();
    window.addEventListener("focus", onFocus);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", onFocus);
    };
  }, [refresh]);

  /** Runs an action, surfaces its error, then re-reads the state. */
  const run = useCallback(
    async (action: () => Promise<unknown>) => {
      setError(null);
      try {
        await action();
      } catch (e) {
        setError(message(e));
      }
      await refresh();
    },
    [refresh],
  );

  const newBriefing = useCallback(async () => {
    if (writing) return; // one model run at a time; briefing.py has no lock of its own
    setWriting(true);
    try {
      await run(api.newBriefing);
    } finally {
      setWriting(false);
    }
  }, [run, writing]);

  const completeTodo = useCallback(
    (id: string) => {
      // Drop it locally first so the fold animation isn't undone by a slow refresh.
      setState((s) => (s ? { ...s, todos: s.todos.filter((t) => t.id !== id) } : s));
      void run(() => api.setTodo(id, true));
    },
    [run],
  );

  const addTodo = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (trimmed) void run(() => api.addTodo(trimmed));
    },
    [run],
  );

  const ask = useCallback(async (question: string) => {
    const q = question.trim();
    if (!q) return;
    setAsking(true);
    setAnswer(null);
    setError(null);
    try {
      const text = await api.ask(q);
      setAnswer(text || "No answer came back. Try asking with a date or a project name.");
    } catch (e) {
      setError(message(e));
    } finally {
      setAsking(false);
    }
  }, []);

  return {
    state,
    phase,
    error,
    writing,
    asking,
    answer,
    briefingVersion,
    refresh,
    newBriefing,
    completeTodo,
    addTodo,
    ask,
    clearAnswer: () => setAnswer(null),
    dismissError: () => setError(null),
    feedback: (up: boolean) => run(() => api.feedback(up)),
    resume: () => run(api.resume),
    setWriter: (backend: string) => run(() => api.setWriter(backend)),
  };
}

export type Briefing = ReturnType<typeof useBriefing>;
