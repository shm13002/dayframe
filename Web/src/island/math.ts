// Small math helpers shared by the island engine (same formulas as the
// liquid-island-motion prototypes).

export type Point = readonly [number, number];

export const TAU = Math.PI * 2;

export const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

/** Hermite smoothstep from a to b. */
export function smooth(a: number, b: number, v: number): number {
  const t = clamp((v - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

/** easeInOutCubic on 0..1. */
export function ease(t: number): number {
  const x = clamp(t, 0, 1);
  return x < 0.5 ? 4 * x * x * x : 1 - (-2 * x + 2) ** 3 / 2;
}

export const rand = (lo: number, hi: number) => lo + Math.random() * (hi - lo);

/** A Catmull-Rom path sampled 24 times per segment, with an arc-length table. */
export interface Path {
  pts: Point[];
  cum: number[];
  len: number;
}

export function buildPath(cp: readonly Point[]): Path {
  const pts: Point[] = [];
  const get = (i: number) => cp[clamp(i, 0, cp.length - 1)] as Point;
  for (let i = 0; i < cp.length - 1; i++) {
    const p0 = get(i - 1);
    const p1 = get(i);
    const p2 = get(i + 1);
    const p3 = get(i + 2);
    for (let k = 0; k < 24; k++) {
      const t = k / 24;
      const t2 = t * t;
      const t3 = t2 * t;
      const f = (a: number, b: number, c: number, d: number) =>
        0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      pts.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
    }
  }
  pts.push(get(cp.length - 1));
  const cum = [0];
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1] as Point;
    const b = pts[i] as Point;
    cum.push((cum[i - 1] as number) + Math.hypot(b[0] - a[0], b[1] - a[1]));
  }
  return { pts, cum, len: cum[cum.length - 1] as number };
}

/** Position and unit normal at fraction s (0..1) along a path. */
export function pointAt(path: Path, s: number): [x: number, y: number, nx: number, ny: number] {
  const target = clamp(s, 0, 1) * path.len;
  let lo = 0;
  let hi = path.cum.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if ((path.cum[mid] as number) < target) lo = mid;
    else hi = mid;
  }
  const a = path.pts[lo] as Point;
  const b = path.pts[hi] as Point;
  const seg = (path.cum[hi] as number) - (path.cum[lo] as number) || 1;
  const u = (target - (path.cum[lo] as number)) / seg;
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const dl = Math.hypot(dx, dy) || 1;
  return [a[0] + dx * u, a[1] + dy * u, -dy / dl, dx / dl];
}

/** Quadratic bezier point. */
export function bezier(p0: Point, p1: Point, p2: Point, u: number): Point {
  const v = 1 - u;
  return [v * v * p0[0] + 2 * v * u * p1[0] + u * u * p2[0], v * v * p0[1] + 2 * v * u * p1[1] + u * u * p2[1]];
}

/** Critically-tuned spring step (semi-implicit Euler), k=230 d=22 like the prototypes. */
export function springStep(x: number, v: number, target: number, dt: number, k = 230, d = 22): [number, number] {
  const nv = v + (k * (target - x) - d * v) * dt;
  return [x + nv * dt, nv];
}

export function formatMinutes(minutes: number): string {
  const m = Math.max(0, Math.round(minutes));
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;
}
