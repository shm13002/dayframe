// Contract between the app (Swift, App/Dayflow/Island) and the island show page.
// All sizes are in points (CSS px inside the WKWebView), measured from the top-left
// of the screen the island runs on.

export type ShowVariant = "startup" | "goal" | "recap";

/** The hardware notch (or a virtual one with width 0 on screens without a notch). */
export interface NotchRect {
  x: number;
  width: number;
  height: number;
}

/** The resting pill the show collapses into; the native pill takes over at the same spot. */
export interface PillSpec {
  leftWing: number;
  rightWing: number;
  height: number;
  radius: number;
}

export interface BriefLine {
  label: string;
  text: string;
}

export interface CategoryMinutes {
  name: string;
  minutes: number;
  color: string;
}

export interface IslandPayload {
  variant: ShowVariant;
  screen: { width: number; height: number };
  notch: NotchRect;
  pill: PillSpec;
  /** "Good evening, Shahzi" */
  greeting: string;
  /** Up to three lines under the greeting (startup only). */
  lines: BriefLine[];
  /** Focus minutes against today's goal; drives the left ring. */
  focus: { minutes: number; goalMinutes: number };
  /** Minutes tracked today; shown in the right wing. */
  trackedMinutes: number;
  /** End-of-day recap: one ring per category. */
  categories: CategoryMinutes[];
  accent: string;
  recording: boolean;
  reducedMotion: boolean;
}

/** Sound cues the page asks the app to play (IslandSound.swift implements each one). */
export type Cue =
  | "drip"
  | "pop"
  | "grain"
  | "bloop"
  | "eyes"
  | "ping1"
  | "ping2"
  | "ping3"
  | "streamStart"
  | "count"
  | "swoosh"
  | "finale"
  | "settle";

export type IslandMessage =
  | { type: "ready" }
  | { type: "cue"; name: Cue; value?: number }
  /** The show is collapsing: the app fades the screen dim out now. */
  | { type: "collapse" }
  /** fps: average frame rate of the show, logged by the app to keep an eye on smoothness. */
  | { type: "done"; fps?: number };
