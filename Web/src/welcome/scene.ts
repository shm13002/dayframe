// The "System Awakening" welcome, drawn in the active Dayframe palette.
//
// Choreography follows the Aether Pulse reference cut and its sound cue sheet
// (first launch: ignition at 2.6 s, three locks at 3.42 / 3.55 / 3.68 s, the
// two-note "online" at 3.8 s). Everything is a pure function of time T, so a
// frozen clock renders the same frame every time (see window.welcome.render).
//
// Sizes are in units of u = screen height / 900, the reference cut's height.

import { clamp, ease, smooth, TAU } from "../island/math";
import { paletteStops, type PaletteName } from "../theme/palettes";

export type WelcomeVariant = "firstLaunch" | "dailyWake";

/** Seconds from start to the "done" message, per variant. */
export const DURATION: Record<WelcomeVariant, number> = { firstLaunch: 5.45, dailyWake: 2.0 };
export const REDUCED_DURATION = 0.8;

// ---------- Colors ----------

type RGB = [number, number, number];

const rgb = (hex: string): RGB => {
  const n = Number.parseInt(hex.replace("#", ""), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const mix = (a: RGB, b: RGB, t: number): RGB => [
  a[0] + (b[0] - a[0]) * t,
  a[1] + (b[1] - a[1]) * t,
  a[2] + (b[2] - a[2]) * t,
];
const scale = (c: RGB, k: number): RGB => [c[0] * k, c[1] * k, c[2] * k];
const css = (c: RGB, alpha = 1) => `rgba(${Math.round(c[0])}, ${Math.round(c[1])}, ${Math.round(c[2])}, ${alpha})`;

export interface WelcomeColors {
  /** Deep version of the palette's dark sky (three stops). */
  sky: [RGB, RGB, RGB];
  /** White-hot center of the light, tinted toward the palette. */
  core: RGB;
  /** The light's body. */
  glow: RGB;
  /** The palette accent, where the light thins out. */
  edge: RGB;
  /** Wordmark and tagline. */
  ink: RGB;
  tag: RGB;
}

export function welcomeColors(palette: PaletteName): WelcomeColors {
  const p = paletteStops(palette);
  const white: RGB = [255, 250, 244];
  const glow = rgb(p.accentLight);
  return {
    sky: [scale(rgb(p.dark[0]), 0.3), scale(rgb(p.dark[1]), 0.22), scale(rgb(p.dark[2]), 0.3)],
    core: mix(white, glow, 0.22),
    glow,
    edge: rgb(p.accent),
    ink: mix(white, glow, 0.12),
    tag: mix([200, 196, 205], glow, 0.35),
  };
}

export function skyGradient(c: WelcomeColors): string {
  return `radial-gradient(140% 120% at 50% 38%, ${css(c.sky[1])} 0%, ${css(c.sky[0])} 55%, ${css(c.sky[2])} 100%)`;
}

// ---------- Deterministic randomness ----------

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Strand {
  phase: number;
  length: number;
  twist: number;
  width: number;
  bright: number;
}

interface Mote {
  angle: number;
  radius: number;
  size: number;
  speed: number;
}

// ---------- Frame state: what's on screen at time T ----------

export interface Frame {
  stage: number;
  stars: number;
  spark: { y: number; alpha: number; size: number } | null;
  streak: number;
  dust: number;
  orbit: { r: number; sweep: number; alpha: number };
  dotted: number;
  vortex: { alpha: number; inner: number; outer: number; spin: number };
  innerRing: number;
  shock: { r: number; alpha: number };
  flash: number;
  eclipse: { r: number; alpha: number; rim: number };
  sparks: number;
  locks: [number, number, number];
  tile: { alpha: number; scale: number };
  word: number;
  tag: number;
}

const LOCK_ANGLES = [-Math.PI / 2, Math.PI / 6, (5 * Math.PI) / 6] as const;

/** A short flash at `at` that settles to `rest` and holds until `until`. */
const blip = (T: number, at: number, rest: number, until = Infinity) =>
  T < at ? 0 : (rest + (1 - rest) * Math.exp(-(T - at) * 14)) * (1 - smooth(until, until + 0.3, T));

function firstLaunch(T: number): Frame {
  const ignite = 2.6;
  // Spark: hangs high, falls to the top of the orbit, then dives into the center.
  let sparkY = -263;
  if (T > 0.8) sparkY = -263 + (263 - 150) * ease((T - 0.8) / 0.8);
  if (T > 1.6) sparkY = -150 + 150 * ease((T - 1.6) / 0.2);
  const spark =
    T < 1.82
      ? { y: sparkY, alpha: smooth(0.08, 0.45, T) * (1 - smooth(1.7, 1.82, T)), size: 0.7 + 0.5 * smooth(0.2, 0.9, T) }
      : null;

  // Eclipse: ignites at 2.6, tightens into the tile from 3.2 s.
  let r = 61;
  if (T > 3.2) r = 61 - 14 * ease((T - 3.2) / 0.55);
  if (T > 3.75) r = 47 - 3 * ease((T - 3.75) / 0.2);

  // Vortex spin accelerates from 1.8 s into the ignition, then winds down.
  const s = Math.max(0, T - 1.75);
  const spin = s < 0.85 ? 0.5 * s + 2.2 * s * s : 0.5 * 0.85 + 2.2 * 0.7225 + 1.2 * (1 - Math.exp(-(s - 0.85) * 1.6));
  const inhale = smooth(2.4, 2.5, T) * (1 - smooth(2.58, 2.62, T));
  const build = smooth(1.72, 1.85, T);
  const outerGrow = 200 + 130 * smooth(1.85, 2.4, T);
  const outerShrink = T < ignite ? outerGrow : 300 + (r + 22 - 300) * ease((T - ignite) / 1.1);
  const vAlpha =
    T < ignite
      ? build * (1 - 0.7 * inhale)
      : 1.25 * Math.exp(-(T - ignite) * 2.2) + (0.3 - 0.14 * smooth(3.6, 4.0, T)) * (1 - smooth(5.0, 5.3, T));

  const confirm = blip(T, 3.8, 0) * 0.35 + blip(T, 3.95, 0) * 0.45;

  return {
    stage: smooth(0, 0.18, T) * (1 - smooth(5.0, 5.4, T)),
    stars: smooth(0.05, 0.6, T) * (1 - 0.6 * smooth(3.6, 4.2, T)),
    spark,
    streak: smooth(0.95, 1.2, T) * (1 - smooth(1.55, 1.75, T)),
    dust: smooth(0.7, 1.0, T) * (1 - smooth(1.7, 1.9, T)),
    orbit: {
      r: 150,
      sweep: ease((T - 0.85) / 0.85),
      alpha: smooth(0.85, 1.0, T) * (1 - 0.4 * smooth(1.8, 2.0, T)) * (1 - smooth(2.45, 2.55, T)),
    },
    dotted: smooth(0.9, 1.3, T) * (1 - smooth(2.4, 2.6, T)),
    vortex: { alpha: Math.max(0, vAlpha), inner: T < ignite ? 61 : r, outer: Math.max(r + 26, outerShrink), spin },
    innerRing: build * (0.25 + 0.75 * Math.exp(-Math.max(0, T - 1.8) * 9)) * (1 - smooth(2.4, 2.5, T)),
    shock: {
      r: 150 + 160 * (1 - Math.exp(-Math.max(0, T - 2.52) * 9)),
      alpha: T < 2.52 ? 0 : 0.9 * (1 - smooth(2.6, 2.95, T)),
    },
    flash: T < ignite ? 0 : Math.exp(-(T - ignite) * 7),
    eclipse: { r, alpha: smooth(2.57, 2.63, T) * (1 - smooth(5.0, 5.35, T)), rim: 1 + confirm },
    sparks: T < ignite ? 0 : 1 - smooth(2.9, 3.4, T),
    locks: [blip(T, 3.42, 0.55, 4.6), blip(T, 3.55, 0.55, 4.6), blip(T, 3.68, 0.55, 4.6)],
    tile: { alpha: smooth(3.75, 4.0, T) * (1 - smooth(4.95, 5.3, T)), scale: 0.94 + 0.06 * ease((T - 3.75) / 0.3) },
    word: smooth(3.95, 4.3, T) * (1 - smooth(4.85, 5.15, T)),
    tag: smooth(4.1, 4.45, T) * (1 - smooth(4.85, 5.1, T)),
  };
}

function dailyWake(T: number): Frame {
  const ignite = 0.32;
  const s = Math.max(0, T - 0.05);
  const spin = s < 0.27 ? 1.5 * s + 9 * s * s : 1.5 * 0.27 + 9 * 0.0729 + 0.9 * (1 - Math.exp(-(s - 0.27) * 2.2));
  const r = T < 0.9 ? 61 : 61 - 9 * ease((T - 0.9) / 0.35);
  const confirm = blip(T, 1.42, 0) * 0.35 + blip(T, 1.56, 0) * 0.45;
  const vAlpha =
    T < ignite
      ? smooth(0.05, 0.2, T) * (1 - 0.6 * smooth(0.26, 0.3, T))
      : 1.2 * Math.exp(-(T - ignite) * 3) + 0.3 * (1 - smooth(1.55, 1.85, T));
  return {
    stage: smooth(0, 0.15, T) * (1 - smooth(1.6, 1.95, T)),
    stars: 0.6 * smooth(0, 0.3, T),
    spark: T < ignite ? { y: 0, alpha: smooth(0, 0.15, T), size: 0.7 + 0.8 * smooth(0, 0.3, T) } : null,
    streak: 0,
    dust: 0,
    orbit: { r: 150, sweep: 0, alpha: 0 },
    dotted: 0,
    vortex: {
      alpha: Math.max(0, vAlpha),
      inner: 61 * (T < ignite ? 0.6 + 0.4 * smooth(0.05, 0.3, T) : r / 61),
      outer: T < ignite ? 90 + 110 * smooth(0.05, 0.3, T) : Math.max(r + 24, 200 - 110 * ease((T - ignite) / 0.55)),
      spin,
    },
    innerRing: 0,
    shock: {
      r: 61 + 180 * (1 - Math.exp(-Math.max(0, T - ignite) * 8)),
      alpha: T < ignite ? 0 : 0.8 * (1 - smooth(0.36, 0.7, T)),
    },
    flash: T < ignite ? 0 : Math.exp(-(T - ignite) * 7),
    eclipse: { r, alpha: smooth(0.29, 0.34, T) * (1 - smooth(1.6, 1.9, T)), rim: 1 + confirm },
    sparks: T < ignite ? 0 : 1 - smooth(0.6, 1.0, T),
    locks: [blip(T, 1.15, 0.55, 1.6), blip(T, 1.24, 0.55, 1.6), blip(T, 1.33, 0.55, 1.6)],
    tile: { alpha: 0, scale: 1 },
    word: 0,
    tag: 0,
  };
}

/** Reduce Motion: the finished mark fades in and out, nothing moves. */
function reduced(variant: WelcomeVariant, T: number): Frame {
  const a = smooth(0, 0.2, T) * (1 - smooth(0.6, 0.8, T));
  const full = variant === "firstLaunch";
  return {
    stage: a,
    stars: 0.5,
    spark: null,
    streak: 0,
    dust: 0,
    orbit: { r: 150, sweep: 0, alpha: 0 },
    dotted: 0,
    vortex: { alpha: 0.3, inner: full ? 44 : 52, outer: full ? 72 : 80, spin: 0 },
    innerRing: 0,
    shock: { r: 0, alpha: 0 },
    flash: 0,
    eclipse: { r: full ? 44 : 52, alpha: 1, rim: 1 },
    sparks: 0,
    locks: [0.55, 0.55, 0.55],
    tile: { alpha: full ? 1 : 0, scale: 1 },
    word: full ? 1 : 0,
    tag: full ? 1 : 0,
  };
}

export function frameAt(variant: WelcomeVariant, T: number, reducedMotion: boolean): Frame {
  if (reducedMotion) return reduced(variant, T);
  return variant === "firstLaunch" ? firstLaunch(T) : dailyWake(T);
}

// ---------- Drawing ----------

export interface Canvases {
  stage: HTMLElement;
  stars: HTMLCanvasElement;
  fx: HTMLCanvasElement;
  bloom: HTMLCanvasElement;
  word: HTMLElement;
  tag: HTMLElement;
  mark: HTMLElement;
}

const STRANDS = 56;
const MOTES = 48;
/** Half-size of the square the light can reach, in u. */
const REACH = 360;
const BLOOM_SCALE = 0.25;

export class WelcomeScene {
  private readonly fx: CanvasRenderingContext2D;
  private readonly bloom: CanvasRenderingContext2D;
  private readonly strands: Strand[];
  private readonly motes: Mote[];
  private readonly dust: Mote[];
  private readonly glowSprite: HTMLCanvasElement;
  private readonly coreSprite: HTMLCanvasElement;
  private u = 1;
  private cx = 0;
  private cy = 0;
  private region = { x: 0, y: 0, size: 0 };

  constructor(
    private readonly el: Canvases,
    private readonly colors: WelcomeColors,
  ) {
    const fx = el.fx.getContext("2d");
    const bloom = el.bloom.getContext("2d");
    if (!fx || !bloom) throw new Error("2D canvas unavailable");
    this.fx = fx;
    this.bloom = bloom;
    el.stage.style.background = skyGradient(colors);
    el.word.style.color = css(colors.ink);
    el.tag.style.color = css(colors.tag, 0.75);

    const rnd = mulberry32(20261012);
    this.strands = Array.from({ length: STRANDS }, (_, i) => ({
      phase: (i / STRANDS) * TAU + (rnd() - 0.5) * 0.18,
      length: 0.55 + rnd() * 0.45,
      twist: 1.5 + rnd() * 0.9,
      width: 0.6 + rnd() * 0.9,
      bright: 0.45 + rnd() * 0.55,
    }));
    this.motes = Array.from({ length: MOTES }, () => ({
      angle: rnd() * TAU,
      radius: rnd(),
      size: 0.5 + rnd() * 1.1,
      speed: 0.6 + rnd() * 0.8,
    }));
    this.dust = Array.from({ length: 40 }, () => ({
      angle: rnd() * TAU,
      radius: Math.sqrt(rnd()),
      size: 0.4 + rnd() * 0.8,
      speed: 0.2 + rnd() * 0.5,
    }));
    this.glowSprite = sprite(colors.glow);
    this.coreSprite = sprite(colors.core);
    this.resize();
  }

  /** Fits the canvases to the window. */
  resize(): void {
    const W = window.innerWidth;
    const H = window.innerHeight;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.u = H / 900;
    this.cx = W / 2;
    this.cy = H * 0.447;
    const size = REACH * 2 * this.u;
    this.region = { x: this.cx - size / 2, y: this.cy - size / 2, size };
    for (const [canvas, k] of [
      [this.el.fx, dpr],
      [this.el.bloom, BLOOM_SCALE],
    ] as const) {
      canvas.width = Math.round(size * k);
      canvas.height = Math.round(size * k);
      canvas.style.width = `${size}px`;
      canvas.style.height = `${size}px`;
      canvas.style.left = `${this.region.x}px`;
      canvas.style.top = `${this.region.y}px`;
    }
    this.fx.setTransform(dpr, 0, 0, dpr, -this.region.x * dpr, -this.region.y * dpr);

    this.drawStars(W, H, dpr);
    const { word, tag, mark } = this.el;
    const u = this.u;
    mark.style.top = `${this.cy + 96 * u}px`;
    word.style.fontSize = `${50 * u}px`;
    word.style.lineHeight = `${54 * u}px`;
    tag.style.fontSize = `${10 * u}px`;
    tag.style.marginTop = `${12 * u}px`;
  }

  private drawStars(W: number, H: number, dpr: number): void {
    const canvas = this.el.stars;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    canvas.style.width = `${W}px`;
    canvas.style.height = `${H}px`;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const rnd = mulberry32(7);
    for (let i = 0; i < 170; i++) {
      const x = rnd() * W;
      const y = rnd() * H;
      const r = (0.35 + rnd() * 0.75) * this.u;
      ctx.fillStyle = css(mix([235, 235, 245], this.colors.glow, rnd() * 0.4), 0.08 + rnd() * 0.32);
      ctx.beginPath();
      ctx.arc(x, y, r, 0, TAU);
      ctx.fill();
    }
  }

  render(f: Frame, T: number): void {
    const { el } = this;
    el.stage.style.opacity = String(f.stage);
    el.stars.style.opacity = String(f.stars);

    const ctx = this.fx;
    const { cx, cy, u } = this;
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
    ctx.restore();

    if (f.tile.alpha > 0) this.drawTile(f, f.tile.alpha);

    ctx.globalCompositeOperation = "lighter";
    ctx.lineCap = "round";

    if (f.dust > 0) {
      for (const m of this.dust) {
        const a = m.angle + T * m.speed * 0.6;
        const rr = m.radius * 140 * u * (1 - 0.25 * smooth(1.0, 1.8, T));
        ctx.fillStyle = css(this.colors.glow, 0.45 * f.dust);
        ctx.fillRect(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr, m.size * u, m.size * u);
      }
    }

    if (f.dotted > 0) {
      ctx.strokeStyle = css(this.colors.glow, 0.42 * f.dotted);
      ctx.lineWidth = 1.1 * u;
      ctx.beginPath();
      const rot = T * 0.12;
      for (let i = 0; i < 64; i++) {
        const a = rot + (i / 64) * TAU;
        const r0 = 192 * u;
        const r1 = 197 * u;
        ctx.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0);
        ctx.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
      }
      ctx.stroke();
    }

    if (f.orbit.alpha > 0 && f.orbit.sweep > 0) {
      const start = -0.26 + T * 0.08;
      ctx.strokeStyle = css(this.colors.core, 0.7 * f.orbit.alpha);
      ctx.lineWidth = 1.3 * u;
      ctx.beginPath();
      ctx.arc(cx, cy, f.orbit.r * u, start, start + f.orbit.sweep * TAU * 0.97);
      ctx.stroke();
    }

    if (f.vortex.alpha > 0.002) this.drawVortex(f);

    if (f.innerRing > 0) this.ring(61 * u, f.innerRing, 1);

    if (f.shock.alpha > 0) {
      ctx.strokeStyle = css(this.colors.core, 0.75 * f.shock.alpha);
      ctx.lineWidth = 1.6 * u;
      ctx.beginPath();
      ctx.arc(cx, cy, f.shock.r * u, 0, TAU);
      ctx.stroke();
    }

    if (f.flash > 0.01) {
      const s = 300 * u * (1 + (1 - f.flash) * 0.4);
      ctx.globalAlpha = 0.55 * f.flash;
      ctx.drawImage(this.glowSprite, cx - s, cy - s, s * 2, s * 2);
      ctx.globalAlpha = 1;
    }

    if (f.sparks > 0) {
      for (const m of this.motes) {
        const life = clamp(f.sparks, 0, 1);
        const rr = (f.eclipse.r + (1 - life) * 140 * m.speed + m.radius * 30) * u;
        const a = m.angle + (1 - life) * 0.6;
        ctx.fillStyle = css(this.colors.core, 0.8 * life);
        ctx.fillRect(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr, m.size * u, m.size * u);
      }
    }

    if (f.eclipse.alpha > 0) this.drawEclipse(f);

    if (f.spark) {
      const y = cy + f.spark.y * u;
      if (f.streak > 0) {
        const g = ctx.createLinearGradient(cx, y - 110 * u, cx, y);
        g.addColorStop(0, css(this.colors.core, 0));
        g.addColorStop(1, css(this.colors.core, 0.75 * f.streak));
        ctx.strokeStyle = g;
        ctx.lineWidth = 1.2 * u;
        ctx.beginPath();
        ctx.moveTo(cx, y - 110 * u);
        ctx.lineTo(cx, y);
        ctx.stroke();
      }
      const s = 26 * u * f.spark.size;
      ctx.globalAlpha = f.spark.alpha;
      ctx.drawImage(this.glowSprite, cx - s, y - s, s * 2, s * 2);
      ctx.drawImage(this.coreSprite, cx - s * 0.32, y - s * 0.32, s * 0.64, s * 0.64);
      ctx.globalAlpha = 1;
    }

    ctx.globalCompositeOperation = "source-over";

    // Bloom: a quarter-size copy of the light; the compositor blurs it.
    const b = this.bloom;
    b.clearRect(0, 0, b.canvas.width, b.canvas.height);
    b.drawImage(this.el.fx, 0, 0, b.canvas.width, b.canvas.height);

    const w = f.word;
    el.word.style.opacity = String(w);
    el.word.style.filter = `blur(${((1 - w) * 6).toFixed(2)}px)`;
    el.word.style.transform = `translateY(${((1 - w) * 6 * u).toFixed(2)}px)`;
    el.tag.style.opacity = String(f.tag * 0.8);
  }

  private drawVortex(f: Frame): void {
    const ctx = this.fx;
    const { cx, cy, u } = this;
    const { inner, outer, spin, alpha } = f.vortex;
    const seg = 26;
    const bands: [number, number, number, number][] = [
      // [from, to, alpha, width]
      [0, 0.28, 0.95, 1.5],
      [0.28, 0.62, 0.5, 1.15],
      [0.62, 1, 0.18, 0.9],
    ];
    const colors = [this.colors.core, this.colors.glow, this.colors.edge];
    for (let b = 0; b < bands.length; b++) {
      const [from, to, a, w] = bands[b] as [number, number, number, number];
      ctx.strokeStyle = css(colors[b] as RGB, Math.min(1, a * alpha));
      for (const s of this.strands) {
        const len = inner + (outer - inner) * s.length;
        ctx.lineWidth = w * s.width * u;
        ctx.globalAlpha = s.bright;
        ctx.beginPath();
        const k0 = Math.floor(from * seg);
        const k1 = Math.ceil(to * seg);
        for (let k = k0; k <= k1; k++) {
          const t = k / seg;
          const r = (inner + (len - inner) * t) * u;
          const a2 = s.phase + spin - s.twist * t ** 0.85;
          const x = cx + Math.cos(a2) * r;
          const y = cy + Math.sin(a2) * r;
          if (k === k0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;
  }

  /** A glowing rim of radius r (points), drawn as three passes from soft to sharp. */
  private ring(r: number, alpha: number, rim: number): void {
    const ctx = this.fx;
    const { cx, cy, u } = this;
    const passes: [RGB, number, number][] = [
      [this.colors.edge, 11, 0.16],
      [this.colors.glow, 5, 0.42],
      [this.colors.core, 2.4, 1],
      [[255, 255, 255], 1.1, 0.9],
    ];
    for (const [c, w, a] of passes) {
      ctx.strokeStyle = css(c, Math.min(1, a * alpha * rim));
      ctx.lineWidth = w * u;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, TAU);
      ctx.stroke();
    }
  }

  private drawEclipse(f: Frame): void {
    const ctx = this.fx;
    const { cx, cy, u } = this;
    const r = f.eclipse.r * u;
    const a = f.eclipse.alpha;
    // Corona sprite, then the dark disc on top, then the rim.
    const s = r * 2.1;
    ctx.globalAlpha = 0.5 * a;
    ctx.drawImage(this.glowSprite, cx - s, cy - s, s * 2, s * 2);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = "source-over";
    ctx.fillStyle = css(this.colors.sky[0], a);
    ctx.beginPath();
    ctx.arc(cx, cy, r - 1.2 * u, 0, TAU);
    ctx.fill();
    ctx.globalCompositeOperation = "lighter";
    this.ring(r, a, f.eclipse.rim);

    for (let i = 0; i < 3; i++) {
      const la = f.locks[i] as number;
      if (la <= 0) continue;
      const ang = LOCK_ANGLES[i] as number;
      ctx.strokeStyle = css(this.colors.core, la * a);
      ctx.lineWidth = 1.6 * u;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(ang) * (r + 3 * u), cy + Math.sin(ang) * (r + 3 * u));
      ctx.lineTo(cx + Math.cos(ang) * (r + 11 * u), cy + Math.sin(ang) * (r + 11 * u));
      ctx.stroke();
    }
  }

  private drawTile(f: Frame, alpha: number): void {
    const ctx = this.fx;
    const { cx, cy, u } = this;
    const half = 74 * u * f.tile.scale;
    const g = ctx.createLinearGradient(cx, cy - half, cx, cy + half);
    g.addColorStop(0, css(mix(this.colors.sky[1], [255, 255, 255], 0.06), alpha));
    g.addColorStop(1, css(this.colors.sky[0], alpha));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.roundRect(cx - half, cy - half, half * 2, half * 2, 30 * u * f.tile.scale);
    ctx.fill();
    ctx.strokeStyle = css(this.colors.glow, 0.38 * alpha);
    ctx.lineWidth = 1 * u;
    ctx.stroke();
  }
}

/** A soft radial glow in one color, drawn with drawImage (far cheaper than shadowBlur). */
function sprite(color: RGB): HTMLCanvasElement {
  const c = document.createElement("canvas");
  c.width = c.height = 128;
  const ctx = c.getContext("2d");
  if (ctx) {
    const g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
    g.addColorStop(0, css(color, 1));
    g.addColorStop(0.18, css(color, 0.55));
    g.addColorStop(0.5, css(color, 0.12));
    g.addColorStop(1, css(color, 0));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 128, 128);
  }
  return c;
}
