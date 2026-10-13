// Talks to the Dayframe app when the page runs inside its WKWebView.
// Swift → page: window.dayframe.setContext({...}) (theme changes without a reload).
// Page → Swift: window.webkit.messageHandlers.dayframe.postMessage({...}).
import { type DayApp, parseDayApps } from "@/briefing/day-apps";
import { applyTheme, isPaletteName, type PaletteName } from "@/theme/palettes";

export interface CategoryColor {
  name: string;
  color: string;
}

export interface HostContext {
  palette: PaletteName;
  dark: boolean;
  categories: CategoryColor[];
  /** The apps from Settings › Start of day. */
  dayApps: DayApp[];
}

export type HostMessage =
  | { type: "ready" }
  | { type: "openURL"; url: string }
  | { type: "openMore"; page: string }
  | { type: "showTimeline" }
  | { type: "openApp"; id: string }
  | { type: "setUpDay" };

interface WebkitHandlers {
  webkit?: { messageHandlers?: { dayframe?: { postMessage: (message: unknown) => void } } };
  dayframe?: { setContext: (context: Partial<HostContext> & { dayApps?: unknown }) => void };
}

const host = window as unknown as Window & WebkitHandlers;

export const isEmbedded = new URLSearchParams(location.search).get("embed") === "dayframe";

export function postToHost(message: HostMessage): boolean {
  const handler = host.webkit?.messageHandlers?.dayframe;
  if (!handler) return false;
  handler.postMessage(message);
  return true;
}

/** Reads the initial context from the URL so the first paint already has the right theme. */
export function initialContext(): HostContext {
  const params = new URLSearchParams(location.search);
  const palette = params.get("palette");
  const theme = params.get("theme");
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  return {
    palette: isPaletteName(palette) ? palette : "original",
    dark: theme ? theme === "dark" : prefersDark,
    categories: [],
    dayApps: [],
  };
}

/**
 * Applies the context now and installs window.dayframe.setContext so the app can
 * push palette, dark mode and category colors later. Returns an unsubscribe.
 */
export function connectHost(onChange: (context: HostContext) => void): () => void {
  let current = initialContext();
  if (isEmbedded) document.documentElement.dataset.embed = "dayframe";
  applyTheme(current.palette, current.dark ? "dark" : "light");
  onChange(current);

  host.dayframe = {
    setContext(next) {
      current = {
        palette: next.palette && isPaletteName(next.palette) ? next.palette : current.palette,
        dark: next.dark ?? current.dark,
        categories: next.categories ?? current.categories,
        dayApps: next.dayApps !== undefined ? parseDayApps(next.dayApps) : current.dayApps,
      };
      applyTheme(current.palette, current.dark ? "dark" : "light");
      onChange(current);
    },
  };

  return () => {
    delete host.dayframe;
  };
}
