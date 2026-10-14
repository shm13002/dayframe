// The Jarvis page runs from a file inside the app (so Hermes trusts its WebSocket origin).
// Swift → page: window.jarvis.setContext({palette, dark, port, token, brain, voice}) and
//               window.jarvis.ask(text, surface) for push-to-talk.
// Page → Swift: window.webkit.messageHandlers.dayframe.postMessage({...}).
import { applyTheme, isPaletteName, type PaletteName } from "@/theme/palettes";
import type { Brain } from "./brains";

export interface JarvisContext {
  palette: PaletteName;
  dark: boolean;
  /** The Hermes backend Swift started; null while it is starting or missing. */
  port: number | null;
  token: string | null;
  /** Why there is no backend yet, in the owner's words. */
  backendNote: string | null;
  /** Settings › Jarvis: the brain new conversations start with. */
  brain: Brain["id"];
}

export type JarvisHostMessage =
  | { type: "ready" }
  | { type: "speak"; text: string }
  | { type: "stopSpeaking" }
  | { type: "busy"; busy: boolean }
  | { type: "listen" }
  | { type: "openSettings" }
  | { type: "failed" };

type AskHandler = (text: string, surface: "voice" | "chat") => void;

interface HostWindow {
  webkit?: { messageHandlers?: { dayframe?: { postMessage: (message: unknown) => void } } };
  jarvis?: {
    setContext: (context: Partial<JarvisContext>) => void;
    ask: (text: string, surface?: "voice" | "chat") => void;
  };
}

const host = window as unknown as Window & HostWindow;

export function postToHost(message: JarvisHostMessage): boolean {
  const handler = host.webkit?.messageHandlers?.dayframe;
  if (!handler) return false;
  handler.postMessage(message);
  return true;
}

export function initialContext(): JarvisContext {
  const params = new URLSearchParams(location.search);
  const palette = params.get("palette");
  const port = Number(params.get("port"));
  return {
    palette: isPaletteName(palette) ? palette : "original",
    dark: params.get("theme") ? params.get("theme") === "dark" : matchMedia("(prefers-color-scheme: dark)").matches,
    port: Number.isInteger(port) && port > 0 ? port : null,
    token: null,
    backendNote: null,
    brain: "grok",
  };
}

/** Installs window.jarvis and applies the theme. Returns an unsubscribe. */
export function connectHost(onChange: (context: JarvisContext) => void, onAsk: AskHandler): () => void {
  let current = initialContext();
  document.documentElement.dataset.embed = "dayframe";
  applyTheme(current.palette, current.dark ? "dark" : "light");
  onChange(current);
  host.jarvis = {
    setContext(next) {
      current = {
        ...current,
        ...next,
        palette: next.palette && isPaletteName(next.palette) ? next.palette : current.palette,
      };
      applyTheme(current.palette, current.dark ? "dark" : "light");
      onChange(current);
    },
    ask(text, surface = "voice") {
      onAsk(text, surface);
    },
  };
  return () => {
    delete host.jarvis;
  };
}
