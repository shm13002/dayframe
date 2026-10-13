// Entry point of the welcome show page.
// Inside Dayframe:  Swift calls window.welcome.play(payload) after "ready". The page posts
//                   "started" on its first frame (Swift starts the sound then), "skip" when
//                   the user clicks or presses a key, and "done" with the measured fps.
// In a browser:     a demo bar plays either cue in any palette. ?variant=…&palette=…&t=…
//                   renders one frozen frame, for side-by-side checks.
import "./welcome.css";
import { isPaletteName, PALETTES, type PaletteName } from "../theme/palettes";
import { DURATION, frameAt, REDUCED_DURATION, type WelcomeVariant, WelcomeScene, welcomeColors } from "./scene";

interface WelcomePayload {
  variant: WelcomeVariant;
  palette: string;
  reducedMotion: boolean;
}

type WelcomeMessage = { type: "ready" | "started" | "skip" } | { type: "done"; fps: number };

interface WelcomeHost {
  webkit?: { messageHandlers?: { welcome?: { postMessage: (m: WelcomeMessage) => void } } };
  welcome?: { play: (p: WelcomePayload) => void; skip: () => void; render: (p: WelcomePayload, t: number) => void };
}

const host = window as unknown as Window & WelcomeHost;
const handler = host.webkit?.messageHandlers?.welcome;
const embedded = handler !== undefined;
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

const elements = {
  stage: $<HTMLElement>("stage"),
  stars: $<HTMLCanvasElement>("stars"),
  fx: $<HTMLCanvasElement>("fx"),
  bloom: $<HTMLCanvasElement>("bloom"),
  word: $<HTMLElement>("wordmark"),
  tag: $<HTMLElement>("tagline"),
  mark: $<HTMLElement>("mark"),
};

const post = (m: WelcomeMessage) => handler?.postMessage(m);

let current: { scene: WelcomeScene; stop: () => void; skip: () => void } | null = null;

function makeScene(p: WelcomePayload): WelcomeScene {
  const palette: PaletteName = isPaletteName(p.palette) ? p.palette : "original";
  return new WelcomeScene(elements, welcomeColors(palette));
}

function play(p: WelcomePayload): void {
  current?.stop();
  const scene = makeScene(p);
  const total = p.reducedMotion ? REDUCED_DURATION : DURATION[p.variant];
  const SKIP_FADE = 0.3;
  let start = -1;
  let frames = 0;
  let skipAt: number | null = null;
  let raf = 0;
  let stopped = false;

  const tick = (now: number) => {
    if (stopped) return;
    if (start < 0) {
      start = now;
      post({ type: "started" });
    }
    const T = (now - start) / 1000;
    frames++;
    const f = frameAt(p.variant, T, p.reducedMotion);
    if (skipAt !== null) f.stage *= 1 - Math.min(1, (T - skipAt) / SKIP_FADE);
    scene.render(f, T);
    const end = skipAt !== null ? skipAt + SKIP_FADE : total;
    if (T >= end) {
      stopped = true;
      elements.stage.style.opacity = "0";
      post({ type: "done", fps: Math.round(frames / Math.max(T, 0.001)) });
      if (!embedded) showDemo(true);
      return;
    }
    raf = requestAnimationFrame(tick);
  };

  const onResize = () => scene.resize();
  window.addEventListener("resize", onResize);
  current = {
    scene,
    stop: () => {
      stopped = true;
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", onResize);
    },
    skip: () => {
      if (skipAt !== null || start < 0) return;
      skipAt = (performance.now() - start) / 1000;
      post({ type: "skip" });
    },
  };
  raf = requestAnimationFrame(tick);
}

/** One frozen frame at time t (seconds), for design checks. */
function render(p: WelcomePayload, t: number): void {
  current?.stop();
  current = null;
  showDemo(false);
  const scene = makeScene(p);
  scene.render(frameAt(p.variant, t, p.reducedMotion), t);
}

host.welcome = { play, skip: () => current?.skip(), render };

if (embedded) {
  window.addEventListener("keydown", () => current?.skip());
  window.addEventListener("pointerdown", () => current?.skip());
  // Fonts are inlined; wait for them so the wordmark never swaps mid-show.
  void document.fonts.ready.then(() => post({ type: "ready" }));
}

// ---------- Browser demo ----------

function showDemo(visible: boolean): void {
  $<HTMLDivElement>("demo").hidden = !visible;
}

if (!embedded) {
  document.documentElement.classList.add("demo");
  const select = $<HTMLSelectElement>("demo-palette");
  for (const name of PALETTES) select.add(new Option(name, name));
  const reduced = $<HTMLInputElement>("demo-reduced");
  const params = new URLSearchParams(location.search);
  const palette = params.get("palette") ?? "original";
  select.value = palette;
  const variant: WelcomeVariant = params.get("variant") === "dailyWake" ? "dailyWake" : "firstLaunch";
  const t = params.get("t");
  for (const button of document.querySelectorAll<HTMLButtonElement>("#demo [data-variant]")) {
    button.addEventListener("click", () => {
      showDemo(false);
      play({ variant: button.dataset.variant as WelcomeVariant, palette: select.value, reducedMotion: reduced.checked });
    });
  }
  window.addEventListener("keydown", (e) => e.key === "Escape" && current?.skip());
  void document.fonts.ready.then(() => {
    if (t !== null) {
      render({ variant, palette, reducedMotion: params.get("reduced") === "1" }, Number(t));
    } else if (params.has("variant")) {
      play({ variant, palette, reducedMotion: params.get("reduced") === "1" });
    } else {
      showDemo(true);
    }
  });
}
