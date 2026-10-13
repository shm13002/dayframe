// Entry point of the island show page.
// Inside Dayframe:  Swift calls window.island.play(payload); the page posts cues and
//                   "collapse"/"done" back through webkit.messageHandlers.island.
// In a browser:     a demo bar plays each show with sample data and Web Audio sound.
import "./island.css";
import { setupCanvas } from "./canvas";
import { canvasRegion, IslandEngine } from "./engine";
import { computeLayout, type Layout } from "./layout";
import { LiquidLayer } from "./liquid";
import { clamp, smooth } from "./math";
import { WebAudioCues } from "./sound";
import { type Timeline, TIMELINES } from "./timelines";
import type { Cue, IslandMessage, IslandPayload, ShowVariant } from "./types";

interface IslandHost {
  webkit?: { messageHandlers?: { island?: { postMessage: (m: IslandMessage) => void } } };
  island?: { play: (payload: IslandPayload) => void; skip: () => void };
}

const host = window as unknown as Window & IslandHost;
const handler = host.webkit?.messageHandlers?.island;
const embedded = handler !== undefined;

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const canvases = {
  goo: $<HTMLCanvasElement>("layer-goo"),
  fx: $<HTMLCanvasElement>("layer-fx"),
  white: $<HTMLCanvasElement>("layer-white"),
};
const copy = $<HTMLElement>("copy");
const greetingEl = $<HTMLHeadingElement>("greeting");
const subtitleEl = $<HTMLParagraphElement>("subtitle");
const linesEl = $<HTMLUListElement>("lines");

const webAudio = new WebAudioCues();
let soundOn = true;
let engine: IslandEngine | null = null;

function post(message: IslandMessage): void {
  if (handler) handler.postMessage(message);
}

function cue(name: Cue, value?: number): void {
  if (embedded) post({ type: "cue", name, value });
  else if (soundOn) webAudio.play(name, value);
}

// ---------- Text layer ----------

const GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

/** Characters resolve left to right out of random glyphs over `duration` seconds. */
function scramble(text: string, progress: number): string {
  const resolved = Math.floor(clamp(progress, 0, 1) * text.length);
  let out = text.slice(0, resolved);
  for (let i = resolved; i < text.length; i++) {
    const ch = text[i] as string;
    out += ch === " " || ch === "," ? ch : (GLYPHS[Math.floor(Math.random() * GLYPHS.length)] as string);
  }
  return out;
}

interface TextState {
  greeting: string;
  subtitle: string;
  lineCount: number;
  shownLines: number;
}

function layoutText(layout: Layout, payload: IslandPayload): TextState {
  const { cx, eyes } = layout;
  copy.style.left = `${cx - 200}px`;
  greetingEl.style.top = `${eyes[1] + 30}px`;
  subtitleEl.style.top = `${eyes[1] + 66}px`;
  linesEl.style.top = `${eyes[1] + 72}px`;

  const startup = payload.variant === "startup";
  linesEl.replaceChildren(
    ...(startup ? payload.lines.slice(0, 3) : []).map((line) => {
      const li = document.createElement("li");
      const label = document.createElement("span");
      label.textContent = line.label;
      li.append(label, line.text);
      return li;
    }),
  );
  greetingEl.textContent = "";
  subtitleEl.textContent = startup ? "" : (payload.lines[0]?.text ?? "");
  copy.style.opacity = "1";
  return { greeting: payload.greeting, subtitle: subtitleEl.textContent, lineCount: linesEl.children.length, shownLines: 0 };
}

function updateText(state: TextState, T: number, tl: Timeline): void {
  const out = 1 - smooth(tl.textOutAt, tl.textOutAt + 0.3, T);
  copy.style.opacity = String(out);
  const g = clamp((T - tl.textAt) / 0.6, 0, 1);
  greetingEl.style.opacity = String(smooth(tl.textAt, tl.textAt + 0.2, T));
  greetingEl.textContent = g >= 1 ? state.greeting : scramble(state.greeting, g);
  subtitleEl.style.opacity = String(smooth(tl.textAt + 0.35, tl.textAt + 0.7, T));
  if (tl.linesAt !== null) {
    const due = clamp(Math.floor((T - tl.linesAt) / 0.15) + 1, 0, state.lineCount);
    while (state.shownLines < due) {
      linesEl.children[state.shownLines]?.classList.add("in");
      state.shownLines++;
    }
  }
}

// ---------- Shows ----------

function play(payload: IslandPayload): void {
  engine?.stop();
  engine = null;
  if (payload.reducedMotion) {
    playReduced(payload);
    return;
  }
  const text: { state: TextState | null } = { state: null };
  const created = new IslandEngine(canvases, payload, {
    cue,
    collapse: () => post({ type: "collapse" }),
    done: (fps) => {
      post({ type: "done", fps: Math.round(fps) });
      if (!embedded) showDemoBar(true);
    },
    tick: (T, tl) => {
      if (text.state) updateText(text.state, T, tl);
    },
  });
  text.state = layoutText(created.layout, payload);
  engine = created;
  created.start();
}

/** Reduce Motion: no liquid or particles. The text fades in on a black card, then out. */
function playReduced(payload: IslandPayload): void {
  const HOLD = 2.6;
  const FADE = 0.3;
  const layout = computeLayout(payload, TIMELINES[payload.variant].banner);
  const { cx, banner } = layout;
  LiquidLayer.clear(canvases.goo);
  LiquidLayer.clear(canvases.white);
  const region = canvasRegion(layout);
  const ctx = setupCanvas(canvases.fx, region, 0);
  const state = layoutText(layout, payload);
  greetingEl.textContent = state.greeting;
  greetingEl.style.opacity = "1";
  subtitleEl.style.opacity = "1";
  for (const li of linesEl.children) li.classList.add("in");
  cue("settle");

  const start = performance.now();
  let collapsed = false;
  const frame = (now: number) => {
    const T = (now - start) / 1000;
    const alpha = smooth(0, FADE, T) * (1 - smooth(HOLD, HOLD + FADE, T));
    ctx.clearRect(region.x, 0, region.w, region.h);
    ctx.globalAlpha = alpha;
    ctx.fillStyle = "#000";
    ctx.beginPath();
    ctx.roundRect(cx - banner.w / 2, 0, banner.w, banner.h, [0, 0, 30, 30]);
    ctx.fill();
    ctx.globalAlpha = 1;
    copy.style.opacity = String(alpha);
    if (!collapsed && T >= HOLD) {
      collapsed = true;
      post({ type: "collapse" });
    }
    if (T < HOLD + FADE + 0.05) requestAnimationFrame(frame);
    else {
      post({ type: "done" });
      if (!embedded) showDemoBar(true);
    }
  };
  requestAnimationFrame(frame);
}

host.island = {
  play,
  skip: () => engine?.skip(),
};

window.addEventListener("pointermove", (e) => engine?.setPointer(e.clientX, e.clientY));
if (embedded) {
  // Any key or click skips ahead to the collapse.
  window.addEventListener("keydown", () => engine?.skip());
  window.addEventListener("pointerdown", () => engine?.skip());
  post({ type: "ready" });
}

// ---------- Browser demo ----------

function samplePayload(variant: ShowVariant, reducedMotion: boolean): IslandPayload {
  const width = window.innerWidth;
  const notchWidth = 196;
  return {
    variant,
    screen: { width, height: window.innerHeight },
    notch: { x: (width - notchWidth) / 2, width: notchWidth, height: 32 },
    pill: { leftWing: 64, rightWing: 84, height: 32, radius: 14 },
    greeting: variant === "goal" ? "Focus goal reached" : variant === "recap" ? "Today, recapped" : "Good evening, Shahzi",
    lines:
      variant === "startup"
        ? [
            { label: "Left off", text: "Designing the Dayframe notch island" },
            { label: "Next", text: "Wire the island into the build and check recording" },
            { label: "Today", text: "3h 7m tracked, 1.8 of 4.5 h focus" },
          ]
        : variant === "goal"
          ? [{ label: "", text: "4h 30m of focus today" }]
          : [{ label: "", text: "6h 12m tracked across 4 categories" }],
    focus: variant === "goal" ? { minutes: 270, goalMinutes: 270 } : { minutes: 108, goalMinutes: 270 },
    trackedMinutes: 187,
    categories: [
      { name: "Studying", minutes: 118, color: "#7b83ff" },
      { name: "Assignments", minutes: 96, color: "#7fd3e8" },
      { name: "Communication", minutes: 41, color: "#f5a97f" },
      { name: "Distraction", minutes: 27, color: "#ff5a4e" },
      { name: "Personal", minutes: 14, color: "#9fe0c8" },
    ],
    accent: "#F3854B",
    recording: true,
    reducedMotion,
  };
}

function showDemoBar(visible: boolean): void {
  $<HTMLDivElement>("demo").hidden = !visible;
}

if (!embedded) {
  document.documentElement.classList.add("demo");
  showDemoBar(true);
  const sound = $<HTMLInputElement>("demo-sound");
  const reduced = $<HTMLInputElement>("demo-reduced");
  sound.addEventListener("change", () => (soundOn = sound.checked));
  for (const button of document.querySelectorAll<HTMLButtonElement>("#demo [data-variant]")) {
    button.addEventListener("click", () => {
      webAudio.unlock();
      showDemoBar(false);
      play(samplePayload(button.dataset.variant as ShowVariant, reduced.checked));
    });
  }
  const params = new URLSearchParams(location.search);
  const auto = params.get("variant");
  if (auto === "startup" || auto === "goal" || auto === "recap") {
    showDemoBar(false);
    play(samplePayload(auto, params.get("reduced") === "1"));
  }
}
