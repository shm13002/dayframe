// Beat sheets for each show, in seconds from the start. Startup follows the
// liquid-island "usage streams" reference (drip, burst, warp, blob, eyes, streams,
// crescents, collapse), stretched so the briefing lines stay up long enough to read.
import type { Cue, ShowVariant } from "./types";

export interface Timeline {
  banner: { w: number; h: number };
  openAt: number;
  warp: readonly [number, number] | null;
  blobAt: number;
  splatAt: number;
  convergeAt: number;
  eyesAt: number;
  blinkAt: number | null;
  winkAt: number | null;
  happy: readonly [number, number] | null;
  textAt: number;
  linesAt: number | null;
  badgesAt: number;
  /** Particles flow while start ≤ T < stopSpawning and are gone by fadeEnd. */
  streams: readonly [start: number, stopSpawning: number, fadeEnd: number];
  count: readonly [start: number, duration: number];
  crescentAt: number;
  textOutAt: number;
  collapseAt: number;
  doneAt: number;
  cues: readonly (readonly [number, Cue])[];
  grains: readonly (readonly [number, number])[];
}

export const TIMELINES: Record<ShowVariant, Timeline> = {
  startup: {
    banner: { w: 860, h: 246 },
    openAt: 0.45,
    warp: [0.5, 1.15],
    blobAt: 0.62,
    splatAt: 1.0,
    convergeAt: 1.35,
    eyesAt: 1.72,
    blinkAt: 2.1,
    winkAt: 2.45,
    happy: [2.64, 2.92],
    textAt: 1.9,
    linesAt: 2.6,
    badgesAt: 3.0,
    streams: [3.1, 5.1, 5.6],
    count: [3.45, 2.2],
    // Text leaves before the crescents launch so they never cross it.
    textOutAt: 5.3,
    crescentAt: 5.6,
    collapseAt: 6.25,
    doneAt: 6.95,
    cues: [
      [0, "drip"],
      [0.45, "pop"],
      [1.02, "bloop"],
      [1.12, "bloop"],
      [1.22, "bloop"],
      [1.7, "eyes"],
      [2.1, "ping1"],
      [2.45, "ping2"],
      [2.64, "ping3"],
      [3.1, "streamStart"],
      [5.6, "swoosh"],
      [6.25, "finale"],
      [6.7, "settle"],
    ],
    grains: [
      [0.5, 1.0],
      [3.2, 5.4],
    ],
  },
  goal: {
    banner: { w: 520, h: 170 },
    openAt: 0.3,
    warp: null,
    blobAt: 0.35,
    splatAt: 0.6,
    convergeAt: 0.72,
    eyesAt: 0.95,
    blinkAt: null,
    winkAt: null,
    happy: [1.15, 1.75],
    textAt: 0.9,
    linesAt: null,
    badgesAt: 0,
    streams: [1.0, 1.8, 2.25],
    count: [1.0, 1.2],
    textOutAt: 1.95,
    crescentAt: 2.1,
    collapseAt: 2.6,
    doneAt: 3.2,
    cues: [
      [0, "drip"],
      [0.3, "pop"],
      [0.95, "eyes"],
      [1.0, "streamStart"],
      [1.15, "ping3"],
      [2.1, "swoosh"],
      [2.25, "finale"],
      [2.9, "settle"],
    ],
    grains: [[1.0, 2.0]],
  },
  recap: {
    banner: { w: 860, h: 310 },
    openAt: 0.45,
    warp: [0.5, 1.0],
    blobAt: 0.55,
    splatAt: 0.85,
    convergeAt: 1.1,
    eyesAt: 1.4,
    blinkAt: 1.8,
    winkAt: null,
    happy: [4.6, 4.9],
    textAt: 1.55,
    linesAt: null,
    badgesAt: 2.0,
    streams: [2.2, 4.0, 4.6],
    count: [2.4, 1.9],
    textOutAt: 4.85,
    crescentAt: 5.0,
    collapseAt: 5.7,
    doneAt: 6.4,
    cues: [
      [0, "drip"],
      [0.45, "pop"],
      [0.9, "bloop"],
      [1.0, "bloop"],
      [1.4, "eyes"],
      [1.8, "ping1"],
      [2.2, "streamStart"],
      [4.6, "ping3"],
      [5.0, "swoosh"],
      [5.7, "finale"],
      [6.15, "settle"],
    ],
    grains: [
      [0.5, 0.95],
      [2.3, 4.3],
    ],
  },
};
