// The liquid notch island: a port of the liquid-island-motion prototypes, driven
// by Dayframe data. Three stacked canvases:
//   goo   black liquid (island, drips), through a blur+threshold "goo" pass (liquid.ts)
//   fx    starfield, warp, streams, eyes, crescents, rings
//   white white liquid (blob, splats, eyes forming), through the same pass
// Text stays real DOM (see main.ts) so it's crisp and readable by VoiceOver.
import { type CanvasRegion, clear, setupCanvas } from "./canvas";
import { computeLayout, type Layout, PILL_TEXT_GAP } from "./layout";
import { LiquidLayer } from "./liquid";
import {
  bezier,
  buildPath,
  clamp,
  ease,
  formatMinutes,
  type Path,
  type Point,
  pointAt,
  rand,
  smooth,
  springStep,
  TAU,
} from "./math";
import { TIMELINES, type Timeline } from "./timelines";
import type { Cue, IslandPayload } from "./types";

const PARTICLE_COLORS = ["#ff5a4e", "#4f8cff", "#34d399", "#a78bfa", "#ffffff", "#ff9f43"] as const;
const TRACK = "#3a3a3c";
const DISC = "#1c1c1e";
const GOO_PAD = 40; // the goo canvas starts this far above the screen so the blur can't eat the top edge
/** Extra room under the banner for drips and ring labels. */
const BELOW_BANNER = 80;
const UI_FONT = '600 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif';

const pick = <T>(list: readonly T[]): T => list[Math.floor(Math.random() * list.length)] as T;

interface Star {
  x: number;
  y: number;
  a: number;
  phase: number;
  color: string;
  size: number;
}

interface Streak {
  x: number;
  y: number;
  v: number;
  color: string;
  dead: boolean;
}

interface StreamParticle {
  path: number;
  s: number;
  v: number;
  off: number;
  wob: number;
  color: string;
  dead: boolean;
}

interface Splat {
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  side: -1 | 1;
  sx: number;
  sy: number;
}

interface CrescentParticle {
  side: 0 | 1;
  delay: number;
  dur: number;
  off: number;
  color: string;
}

interface Ring {
  x: number;
  y: number;
  color: string;
  name: string;
  minutes: number;
  fraction: number;
}

export interface EngineCanvases {
  goo: HTMLCanvasElement;
  fx: HTMLCanvasElement;
  white: HTMLCanvasElement;
}

export interface EngineCallbacks {
  cue: (name: Cue, value?: number) => void;
  collapse: () => void;
  done: (fps: number) => void;
  /** Seconds since start, for the DOM text layer. */
  tick: (t: number, timeline: Timeline) => void;
}

interface Body {
  x: number;
  w: number;
  h: number;
  r: number;
  vx: number;
  vw: number;
  vh: number;
  vr: number;
}

export class IslandEngine {
  readonly timeline: Timeline;
  readonly layout: Layout;
  private readonly payload: IslandPayload;
  private readonly cb: EngineCallbacks;
  private readonly gooLayer: LiquidLayer;
  private readonly whiteLayer: LiquidLayer;
  private readonly goo: CanvasRenderingContext2D;
  private readonly fx: CanvasRenderingContext2D;
  private readonly white: CanvasRenderingContext2D;

  private body: Body;
  private t0 = 0;
  private last = 0;
  private raf = 0;
  private fired = new Set<number>();
  private collapsed = false;
  private finished = false;
  private pointer: Point;
  private nextBlink = 0;
  private lastCountAt = 0;
  private lastCountValue = -1;
  private frames = 0;

  private readonly stars: Star[] = [];
  private warp: Streak[] = [];
  private warpSpawned = 0;
  private stream: StreamParticle[] = [];
  private splats: Splat[] | null = null;
  private crescent: CrescentParticle[] | null = null;
  private readonly rings: Ring[];
  private readonly ringPaths: Path[];

  constructor(canvases: EngineCanvases, payload: IslandPayload, callbacks: EngineCallbacks) {
    this.payload = payload;
    this.cb = callbacks;
    this.timeline = TIMELINES[payload.variant];
    this.layout = computeLayout(payload, this.timeline.banner);
    const { pillRect, cx, eyes } = this.layout;
    // The canvases cover only the island's area, not the whole screen: the goo blur is the
    // most expensive step, and its cost grows with the canvas size.
    const region = canvasRegion(this.layout);
    this.gooLayer = LiquidLayer.for(canvases.goo, [0, 0, 0]);
    this.whiteLayer = LiquidLayer.for(canvases.white, [1, 1, 1]);
    this.goo = this.gooLayer.setup(region, GOO_PAD);
    this.fx = setupCanvas(canvases.fx, region, 0);
    this.white = this.whiteLayer.setup(region, GOO_PAD);
    this.pointer = [cx, eyes[1] + 120];

    // The show starts from the resting pill that was on screen.
    this.body = {
      x: pillRect.x + pillRect.w / 2,
      w: pillRect.w,
      h: pillRect.h,
      r: pillRect.r,
      vx: 0,
      vw: 0,
      vh: 0,
      vr: 0,
    };

    for (let i = 0; i < 130; i++) {
      this.stars.push({
        x: Math.random(),
        y: Math.random(),
        a: rand(0.2, 0.8),
        phase: rand(0, TAU),
        color: PARTICLE_COLORS[i % PARTICLE_COLORS.length] as string,
        size: Math.random() < 0.2 ? 1.6 : 1,
      });
    }

    this.rings = payload.variant === "recap" ? this.recapRings() : [];
    // Recap streams fan out from just under the title text (never through it) into each ring.
    this.ringPaths = this.rings.map((ring) => {
      const [ex, ey] = eyes;
      const top = ey + 102;
      return buildPath([
        [ex + (ring.x - ex) * 0.08, top],
        [ex + (ring.x - ex) * 0.55, top + 8],
        [ring.x, ring.y - 34],
        [ring.x, ring.y - 22],
      ]);
    });
    const targets = this.rings.length > 0 ? this.ringPaths.length : 2;
    for (let p = 0; p < targets; p++) {
      for (let i = 0; i < (this.rings.length > 0 ? 70 : 130); i++) {
        this.stream.push({
          path: p,
          s: -Math.random() * 0.9,
          v: rand(0.32, 0.54),
          off: rand(-9, 9),
          wob: rand(0, TAU),
          color: this.rings[p]?.color ?? pick(PARTICLE_COLORS),
          dead: false,
        });
      }
    }
  }

  start(): void {
    this.t0 = performance.now();
    this.last = this.t0;
    this.nextBlink = this.t0 + 2600;
    const tick = (now: number) => {
      this.frame(now);
      if (!this.finished) this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  }

  stop(): void {
    cancelAnimationFrame(this.raf);
    this.finished = true;
  }

  /** Any key or click: jump to the collapse. */
  skip(): void {
    const t = (performance.now() - this.t0) / 1000;
    const target = this.timeline.textOutAt;
    if (t < target) this.t0 -= (target - t) * 1000;
    this.stream.forEach((q) => (q.dead = true));
    this.crescent = [];
  }

  setPointer(x: number, y: number): void {
    this.pointer = [x, y];
  }

  /** Values the counters land on. */
  private get targets() {
    const { focus, trackedMinutes } = this.payload;
    const pct = focus.goalMinutes > 0 ? Math.round((focus.minutes / focus.goalMinutes) * 100) : 0;
    return { focusPct: Math.min(pct, 999), tracked: Math.round(trackedMinutes) };
  }

  private recapRings(): Ring[] {
    const cats = this.payload.categories
      .filter((c) => c.minutes > 0)
      .sort((a, b) => b.minutes - a.minutes)
      .slice(0, 5);
    const max = Math.max(1, ...cats.map((c) => c.minutes));
    const spacing = Math.min(140, (this.layout.banner.w - 140) / Math.max(cats.length, 1));
    const y = this.timeline.banner.h - 82;
    return cats.map((c, i) => ({
      x: this.layout.cx + (i - (cats.length - 1) / 2) * spacing,
      y,
      color: c.color,
      name: c.name,
      minutes: c.minutes,
      fraction: c.minutes / max,
    }));
  }

  private bodyTarget(T: number): [x: number, w: number, h: number, r: number] {
    const { pillRect, notchRect, banner, cx } = this.layout;
    const tl = this.timeline;
    const pill: [number, number, number, number] = [pillRect.x + pillRect.w / 2, pillRect.w, pillRect.h, pillRect.r];
    if (T >= tl.collapseAt) return pill;
    if (T >= tl.openAt) return [cx, banner.w, banner.h, 30];
    // Before the burst: shrink back to the bare notch while the drip forms.
    return [cx, Math.max(notchRect.w, 120), notchRect.h, 10];
  }

  private frame(now: number): void {
    // Clamp so a hitch can't make the springs jump, but allow ~20 fps without slowing the show.
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    const T = (now - this.t0) / 1000;
    const t = now / 1000;
    const tl = this.timeline;
    this.frames++;

    this.fireCues(T);
    this.stepBody(T, dt);

    const b = this.body;
    const W = Math.max(60, b.w);
    const H = Math.max(18, b.h);
    const R = Math.max(4, b.r);

    this.drawGoo(T, W, H, R);
    this.gooLayer.present();
    this.drawFx(T, t, now, dt, W, H, R);
    this.whiteLayer.present(!this.drawWhite(T, t, dt));
    this.cb.tick(T, tl);

    if (!this.collapsed && T >= tl.collapseAt) {
      this.collapsed = true;
      this.cb.collapse();
    }
    // Hand over to the native pill once the spring has settled.
    const settled = Math.abs(b.vw) + Math.abs(b.vh) + Math.abs(b.vx) < 4;
    if (!this.finished && T >= tl.doneAt && (settled || T >= tl.doneAt + 0.6)) {
      this.finished = true;
      this.cb.done(T > 0 ? this.frames / T : 0);
    }
  }

  private fireCues(T: number): void {
    const tl = this.timeline;
    tl.cues.forEach(([at, name], i) => {
      if (T >= at && !this.fired.has(i)) {
        this.fired.add(i);
        if (T - at < 0.3) this.cb.cue(name); // skipped-over cues stay silent
      }
    });
    for (const [a, z] of tl.grains) {
      if (T > a && T < z && Math.random() < 0.5 && !this.collapsed) this.cb.cue("grain");
    }
  }

  private stepBody(T: number, dt: number): void {
    const [tx, tw, th, tr] = this.bodyTarget(T);
    const b = this.body;
    [b.x, b.vx] = springStep(b.x, b.vx, tx, dt);
    [b.w, b.vw] = springStep(b.w, b.vw, tw, dt);
    [b.h, b.vh] = springStep(b.h, b.vh, th, dt);
    [b.r, b.vr] = springStep(b.r, b.vr, tr, dt);
  }

  // ---------- Black liquid ----------
  private drawGoo(T: number, W: number, H: number, R: number): void {
    const g = this.goo;
    const { cx, notchRect } = this.layout;
    clear(g);
    g.fillStyle = "#000";
    // Drawn from the canvas top (GOO_PAD above the screen) so the filter can't round off the top edge.
    g.beginPath();
    g.roundRect(this.body.x - W / 2, 0, W, H + GOO_PAD, [0, 0, R, R]);
    g.fill();

    // The hardware notch never moves: keep it solid while the island reshapes around it.
    g.fillRect(notchRect.x, 0, notchRect.w, notchRect.h + GOO_PAD);

    // Drips hang from the bottom edge while the island grows and tuck in as it shrinks.
    if (H > 40) {
      const lag = clamp(this.body.vh * 0.045, -24, 34);
      for (let i = 0; i < 7; i++) {
        const bx = this.body.x + (i - 3) * W * 0.14;
        const by = GOO_PAD + H - 10 + lag * (0.55 + 0.45 * Math.sin(i * 2.1 + 1));
        g.beginPath();
        g.arc(bx, by, 10, 0, TAU);
        g.fill();
      }
    }

    // The first drop leaves the notch before the burst.
    const { openAt } = this.timeline;
    if (T < openAt + 0.05) {
      const e = ease(T / Math.max(openAt - 0.03, 0.1));
      const base = GOO_PAD + notchRect.h;
      const cy = base + 4 + e * 30;
      g.beginPath();
      g.arc(cx, cy, 11, 0, TAU);
      g.fill();
      g.beginPath();
      g.arc(cx, base + (cy - base) * 0.45, 7, 0, TAU);
      g.fill();
    }
  }

  // ---------- Effects ----------
  private drawFx(T: number, t: number, now: number, dt: number, W: number, H: number, R: number): void {
    const c = this.fx;
    const tl = this.timeline;
    const { eyes } = this.layout;
    clear(c);

    const open = clamp((H - 60) / 120, 0, 1);
    const ix = this.body.x - W / 2;
    if (open > 0) {
      c.save();
      c.beginPath();
      c.roundRect(ix + 6, 0, W - 12, H - 6, Math.max(4, R - 4));
      c.clip();

      // Faint glow behind the eyes.
      const glow = c.createRadialGradient(eyes[0], eyes[1], 0, eyes[0], eyes[1], 170);
      glow.addColorStop(0, `rgba(255,255,255,${0.055 * open})`);
      glow.addColorStop(1, "rgba(255,255,255,0)");
      c.fillStyle = glow;
      c.fillRect(ix, 0, W, H);

      for (const s of this.stars) {
        c.globalAlpha = s.a * (0.5 + 0.5 * Math.sin(t * 1.5 + s.phase)) * open;
        c.fillStyle = s.color;
        c.fillRect(ix + 10 + ((s.x + t * 0.004) % 1) * (W - 20), 36 + s.y * (H - 50), s.size, s.size);
      }
      c.globalAlpha = 1;

      if (tl.warp) this.drawWarp(T, dt, tl.warp);
      this.drawStreams(T, t, dt);
      this.drawRings(T);
      this.drawEyes(T, now);
      this.drawCrescents(T);
      c.restore();
    }

    this.drawPillContent(T);
  }

  private drawWarp(T: number, dt: number, [start, end]: readonly [number, number]): void {
    const c = this.fx;
    const [ex, ey] = this.layout.eyes;
    if (T >= start && T < end) {
      const want = Math.floor(170 * clamp((T - start) / 0.3, 0, 1));
      while (this.warpSpawned < want) {
        this.warpSpawned++;
        const a = rand(0, TAU);
        const d = rand(170, 390);
        this.warp.push({
          x: ex + Math.cos(a) * d,
          y: ey + Math.sin(a) * d * 0.34,
          v: 60,
          color: pick(PARTICLE_COLORS),
          dead: false,
        });
      }
    }
    c.lineCap = "round";
    for (const q of this.warp) {
      if (q.dead) continue;
      const dx = ex - q.x;
      const dy = ey - q.y;
      const dl = Math.hypot(dx, dy) || 1;
      const ux = dx / dl;
      const uy = dy / dl;
      q.v += 900 * dt;
      q.x += ux * q.v * dt;
      q.y += uy * q.v * dt;
      if (dl < 14) {
        q.dead = true;
        continue;
      }
      const len = Math.min(26, q.v * 0.04);
      c.strokeStyle = q.color;
      c.lineWidth = 1.6;
      c.globalAlpha = 0.85;
      c.beginPath();
      c.moveTo(q.x - ux * len, q.y - uy * len);
      c.lineTo(q.x, q.y);
      c.stroke();
      c.fillStyle = q.color;
      c.beginPath();
      c.arc(q.x, q.y, 1.4, 0, TAU);
      c.fill();
    }
    c.globalAlpha = 1;
  }

  private drawStreams(T: number, t: number, dt: number): void {
    const [start, stopSpawning, fadeEnd] = this.timeline.streams;
    if (T < start) return;
    const c = this.fx;
    const paths = this.rings.length > 0 ? this.ringPaths : this.layout.sidePaths;
    const alpha = smooth(start, start + 0.4, T) * (1 - smooth(fadeEnd - 0.4, fadeEnd, T));
    if (alpha <= 0) return;
    c.lineCap = "round";
    for (const q of this.stream) {
      if (q.dead) continue;
      q.s += q.v * dt;
      if (q.s > 1) {
        if (T < stopSpawning) q.s -= rand(1.05, 1.15);
        else {
          q.dead = true;
          continue;
        }
      }
      if (q.s < 0.02) continue;
      const path = paths[q.path];
      if (!path) continue;
      const wob = q.off + Math.sin(t * 3 + q.wob) * 3;
      const head = pointAt(path, q.s);
      const tail = pointAt(path, q.s - 0.025);
      const hx = head[0] + head[2] * wob;
      const hy = head[1] + head[3] * wob;
      c.globalAlpha = alpha * smooth(0.02, 0.08, q.s) * (1 - smooth(0.94, 1, q.s));
      c.strokeStyle = q.color;
      c.lineWidth = 1.8;
      c.beginPath();
      c.moveTo(tail[0] + tail[2] * wob, tail[1] + tail[3] * wob);
      c.lineTo(hx, hy);
      c.stroke();
      c.fillStyle = q.color;
      c.beginPath();
      c.arc(hx, hy, 1.5, 0, TAU);
      c.fill();
    }
    c.globalAlpha = 1;
  }

  private countProgress(T: number, stagger = 0): number {
    const [start, duration] = this.timeline.count;
    return ease((T - start - stagger) / duration);
  }

  /** Recap: one ring per category, filled by its stream, minutes counting up beneath. */
  private drawRings(T: number): void {
    if (this.rings.length === 0) return;
    const c = this.fx;
    const tl = this.timeline;
    const alpha = smooth(tl.badgesAt, tl.badgesAt + 0.3, T) * (1 - smooth(tl.textOutAt, tl.textOutAt + 0.3, T));
    if (alpha <= 0) return;
    c.save();
    c.globalAlpha = alpha;
    this.rings.forEach((ring, i) => {
      const p = this.countProgress(T, i * 0.12);
      c.lineWidth = 3;
      c.strokeStyle = TRACK;
      c.beginPath();
      c.arc(ring.x, ring.y, 18, 0, TAU);
      c.stroke();
      if (p > 0) {
        c.strokeStyle = ring.color;
        c.lineCap = "round";
        c.beginPath();
        c.arc(ring.x, ring.y, 18, -Math.PI / 2, -Math.PI / 2 + TAU * ring.fraction * p);
        c.stroke();
      }
      c.fillStyle = "#ffffff";
      c.font = UI_FONT;
      c.textAlign = "center";
      c.textBaseline = "middle";
      c.fillText(formatMinutes(ring.minutes * p), ring.x, ring.y + 34);
      c.fillStyle = "#8a8a8e";
      c.font = '400 11px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif';
      c.fillText(truncate(c, ring.name, 110), ring.x, ring.y + 50);
    });
    c.restore();
  }

  private blinkOpen(now: number): number {
    if (now < this.nextBlink) return 1;
    const b = (now - this.nextBlink) / 170;
    if (b >= 1) {
      this.nextBlink = now + rand(2500, 5500);
      return 1;
    }
    return 1 - Math.sin(b * Math.PI) * 0.9;
  }

  private drawEyes(T: number, now: number): void {
    const tl = this.timeline;
    if (T < tl.eyesAt || T >= tl.crescentAt + 0.25) return;
    const c = this.fx;
    const [ex0, ey0] = this.layout.eyes;
    const shrink = 1 - smooth(tl.crescentAt, tl.crescentAt + 0.25, T);
    const lookX = clamp((this.pointer[0] - ex0) / 300, -1, 1) * 5;
    const lookY = clamp((this.pointer[1] - ey0) / 220, -1, 1) * 3;
    const happy = tl.happy !== null && T > tl.happy[0] && T < tl.happy[1];
    let left = this.blinkOpen(now);
    if (tl.blinkAt !== null) left *= 1 - 0.92 * Math.sin(clamp((T - tl.blinkAt) / 0.15, 0, 1) * Math.PI);
    let right = left;
    if (tl.winkAt !== null) right *= 1 - 0.92 * Math.sin(clamp((T - tl.winkAt) / 0.2, 0, 1) * Math.PI);

    c.fillStyle = "#ffffff";
    c.strokeStyle = "#ffffff";
    for (const side of [-1, 1] as const) {
      const ex = ex0 + side * 13 + lookX;
      const ey = ey0 + lookY;
      if (happy) {
        c.lineWidth = 3;
        c.lineCap = "round";
        c.beginPath();
        c.arc(ex, ey + 4, 6.5, Math.PI * 1.15, Math.PI * 1.85);
        c.stroke();
      } else {
        const openness = side < 0 ? left : right;
        const w = 12 * shrink;
        const h = Math.max(2, 20 * openness * shrink);
        c.beginPath();
        c.roundRect(ex - w / 2, ey - h / 2, w, h, Math.min(w, h) / 2);
        c.fill();
      }
    }
  }

  /** The eyes break into two crescents that fly into the pill's ring and eyes. */
  private drawCrescents(T: number): void {
    const at = this.timeline.crescentAt;
    if (T < at || T >= at + 0.9) return;
    if (!this.crescent) {
      this.crescent = [];
      for (const side of [0, 1] as const) {
        for (let i = 0; i < 70; i++) {
          this.crescent.push({
            side,
            delay: rand(0, 0.35),
            dur: rand(0.45, 0.6),
            off: rand(-7, 7),
            color: Math.random() < 0.5 ? "#ffffff" : pick(PARTICLE_COLORS),
          });
        }
      }
    }
    const c = this.fx;
    c.lineCap = "round";
    for (const q of this.crescent) {
      const u = clamp((T - at - q.delay) / q.dur, 0, 1);
      if (u <= 0 || u >= 1) continue;
      const e = ease(u);
      const [p0, p1, p2] = this.layout.crescents[q.side];
      const a = bezier(p0, p1, p2, e);
      const b = bezier(p0, p1, p2, Math.max(0, e - 0.08));
      const o = q.off * (1 - e);
      c.globalAlpha = 1 - smooth(0.85, 1, u);
      c.strokeStyle = q.color;
      c.lineWidth = 2.2;
      c.beginPath();
      c.moveTo(b[0] + o, b[1] + o);
      c.lineTo(a[0] + o, a[1] + o);
      c.stroke();
    }
    c.globalAlpha = 1;
  }

  /** The focus ring on the left of the notch and the eyes + time on the right. */
  private drawPillContent(T: number): void {
    const c = this.fx;
    const tl = this.timeline;
    const { leftBadge, rightEyes, rightText } = this.layout;
    const { focusPct, tracked } = this.targets;
    // The resting pill's content fades out as the show starts, then comes back counting.
    // The goal show keeps it on screen: its ring is what fills up.
    const keep = this.payload.variant === "goal";
    const leaving = 1 - smooth(0, 0.25, T);
    const arriving = smooth(tl.badgesAt, tl.badgesAt + 0.3, T);
    const alpha = keep ? 1 : Math.max(leaving, arriving);
    if (alpha <= 0) return;

    let pct: number;
    let minutes: number;
    if (!keep && leaving > arriving) {
      pct = focusPct;
      minutes = tracked;
    } else if (keep) {
      const from = Math.min(focusPct, 99);
      pct = Math.round(from + (Math.max(100, focusPct) - from) * this.countProgress(T));
      minutes = tracked;
    } else {
      const p = this.countProgress(T);
      pct = Math.round(focusPct * p);
      minutes = Math.round(tracked * this.countProgress(T, 0.1));
    }
    if (
      pct !== this.lastCountValue &&
      T > tl.count[0] &&
      performance.now() - this.lastCountAt > 65 &&
      !this.collapsed
    ) {
      this.lastCountAt = performance.now();
      this.cb.cue("count", Math.min(pct, 100));
    }
    this.lastCountValue = pct;

    c.save();
    c.globalAlpha = alpha;
    drawFocusRing(c, leftBadge, pct, this.payload.accent);
    c.fillStyle = "#ffffff";
    c.font = UI_FONT;
    c.textAlign = "left";
    c.textBaseline = "middle";
    c.fillText(`${pct}%`, leftBadge[0] + PILL_TEXT_GAP, leftBadge[1] + 0.5);

    // Small eyes appear once the crescent lands (or right away when not mid-show).
    const eyesIn = Math.max(leaving, smooth(tl.crescentAt + 0.45, tl.crescentAt + 0.7, T));
    if (eyesIn > 0) {
      c.globalAlpha = alpha * eyesIn;
      drawSmallEyes(c, rightEyes, this.payload.recording);
      c.globalAlpha = alpha;
    }
    c.fillStyle = "#ffffff";
    c.fillText(formatMinutes(minutes), rightText[0], rightText[1] + 0.5);
    c.restore();
  }

  // ---------- White liquid ----------
  /** Returns false when there's nothing to draw this frame. */
  private drawWhite(T: number, t: number, dt: number): boolean {
    const g = this.white;
    const tl = this.timeline;
    clear(g);
    if (T < tl.blobAt || T >= tl.eyesAt + 0.05) return false;
    const [ex, ey0] = this.layout.eyes;
    const ey = ey0 + GOO_PAD;
    g.fillStyle = "#ffffff";

    if (T < tl.splatAt) {
      const R = 6 + 16 * ease((T - tl.blobAt) / (tl.splatAt - tl.blobAt));
      g.beginPath();
      g.arc(ex, ey, R, 0, TAU);
      g.fill();
      for (let i = 0; i < 4; i++) {
        const a = t * 6 + i * 1.57;
        g.beginPath();
        g.arc(ex + Math.cos(a) * R * 0.6, ey + Math.sin(a) * R * 0.6, R * 0.5, 0, TAU);
        g.fill();
      }
      return true;
    }

    if (!this.splats) {
      this.splats = [];
      for (let i = 0; i < 16; i++) {
        this.splats.push({
          x: ex + rand(-8, 8),
          y: ey + rand(-6, 6),
          vx: rand(-260, 260),
          vy: rand(-90, 30),
          r: rand(3, 9),
          side: i % 2 ? 1 : -1,
          sx: 0,
          sy: 0,
        });
      }
    }
    const span = tl.eyesAt - tl.convergeAt - 0.05;
    for (const q of this.splats) {
      if (T < tl.convergeAt) {
        q.vy += 520 * dt;
        q.vx *= 0.97;
        q.x += q.vx * dt;
        q.y = Math.min(q.y + q.vy * dt, ey + 82);
        q.sx = q.x;
        q.sy = q.y;
      } else {
        const e = ease((T - tl.convergeAt) / span);
        q.x = q.sx + (ex + q.side * 13 - q.sx) * e;
        q.y = q.sy + (ey - q.sy) * e;
      }
      const rr = T < tl.convergeAt ? q.r : q.r + (5 - q.r) * ease((T - tl.convergeAt) / span);
      g.beginPath();
      g.arc(q.x, q.y, rr, 0, TAU);
      g.fill();
    }
    if (T > tl.eyesAt - 0.14) {
      const grow = ease((T - (tl.eyesAt - 0.14)) / 0.14);
      for (const side of [-1, 1]) {
        g.beginPath();
        g.ellipse(ex + side * 13, ey, 6 * grow + 0.1, 10 * grow + 0.1, 0, 0, TAU);
        g.fill();
      }
    }
    return true;
  }
}

export function canvasRegion(layout: Layout): CanvasRegion {
  const w = Math.min(layout.screenW, Math.ceil(layout.banner.w + 160));
  const x = Math.max(0, Math.min(layout.screenW - w, Math.floor(layout.cx - w / 2)));
  return { x, w, h: Math.ceil(layout.banner.h + BELOW_BANNER) };
}

/** Same drawing as the native pill's FocusRing: track, accent arc from 12 o'clock, dark disc, dot. */
function drawFocusRing(c: CanvasRenderingContext2D, [x, y]: Point, pct: number, accent: string): void {
  c.lineWidth = 2.4;
  c.strokeStyle = TRACK;
  c.beginPath();
  c.arc(x, y, 9, 0, TAU);
  c.stroke();
  if (pct > 0) {
    c.strokeStyle = accent;
    c.lineCap = "round";
    c.beginPath();
    c.arc(x, y, 9, -Math.PI / 2, -Math.PI / 2 + (TAU * Math.min(pct, 100)) / 100);
    c.stroke();
  }
  c.fillStyle = DISC;
  c.beginPath();
  c.arc(x, y, 7, 0, TAU);
  c.fill();
  c.fillStyle = accent;
  c.beginPath();
  c.arc(x, y, 2.4, 0, TAU);
  c.fill();
}

/** Two small capsules; closed (thin lines) while recording is paused. */
function drawSmallEyes(c: CanvasRenderingContext2D, [x, y]: Point, open: boolean): void {
  c.fillStyle = "#ffffff";
  for (const side of [-1, 1]) {
    const w = 4;
    const h = open ? 9 : 2;
    c.beginPath();
    c.roundRect(x + side * 4 - w / 2, y - h / 2, w, h, w / 2);
    c.fill();
  }
}

function truncate(c: CanvasRenderingContext2D, text: string, max: number): string {
  if (c.measureText(text).width <= max) return text;
  let s = text;
  while (s.length > 1 && c.measureText(`${s}…`).width > max) s = s.slice(0, -1);
  return `${s}…`;
}
