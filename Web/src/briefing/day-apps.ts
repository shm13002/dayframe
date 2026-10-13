// The day apps the Dayframe app sends with its context (Settings › Start of day). The page
// shows them as a row; clicking one asks the app to bring it forward.

export interface DayApp {
  /** The app's bundle ID; the only thing the page sends back. */
  id: string;
  name: string;
  /** A small PNG as a data URL (briefing.py's CSP allows data: images). */
  icon: string;
}

const PNG_DATA_URL = /^data:image\/png;base64,[A-Za-z0-9+/=]+$/;

/** Keeps only well-formed entries: a bundle ID, a name and a PNG data-URL icon. */
export function parseDayApps(raw: unknown): DayApp[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item): DayApp[] => {
    if (typeof item !== "object" || item === null) return [];
    const { id, name, icon } = item as Record<string, unknown>;
    if (typeof id !== "string" || !/^[\w.-]+$/.test(id)) return [];
    if (typeof name !== "string" || name.trim() === "") return [];
    if (typeof icon !== "string" || !PNG_DATA_URL.test(icon)) return [];
    return [{ id, name: name.trim(), icon }];
  });
}
