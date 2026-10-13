// Where everything sits, derived from the real notch and the native pill spec.
// The native pill (App/Dayflow/Island/NotchPillView.swift) uses the same offsets,
// so the show's last frame and the pill's first frame line up exactly.
import { buildPath, type Path, type Point } from "./math";
import type { IslandPayload } from "./types";

export const PILL_BADGE_INSET = 18; // left ring center, from the pill's left edge
export const PILL_TEXT_GAP = 16; // ring center to its percentage text
export const PILL_EYES_INSET = 16; // right eyes center, from the notch's right edge
export const PILL_TIME_INSET = 30; // right time text, from the notch's right edge

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
  r: number;
}

export interface Layout {
  screenW: number;
  /** Center x of the notch: the island grows from here. */
  cx: number;
  notchRect: Rect;
  pillRect: Rect;
  banner: { w: number; h: number };
  eyes: Point;
  leftBadge: Point;
  rightEyes: Point;
  rightText: Point;
  /** Streams from the banner's bottom corners into the left ring and the right wing. */
  sidePaths: [Path, Path];
  /** Eye crescents into the same two targets. */
  crescents: [readonly [Point, Point, Point], readonly [Point, Point, Point]];
}

export function computeLayout(p: IslandPayload, banner: { w: number; h: number }): Layout {
  const { notch, pill } = p;
  const cx = notch.x + notch.width / 2;
  const notchRight = notch.x + notch.width;
  const pillX = notch.x - pill.leftWing;
  const pillW = notch.width + pill.leftWing + pill.rightWing;
  const midY = pill.height / 2;
  const w = Math.min(banner.w, p.screen.width - 32);
  const h = banner.h;

  const leftBadge: Point = [pillX + PILL_BADGE_INSET, midY];
  const rightEyes: Point = [notchRight + PILL_EYES_INSET, midY];
  const rightText: Point = [notchRight + PILL_TIME_INSET, midY];
  const eyes: Point = [cx, 76];

  // The prototype's S-curves (drawn for a 720×220 banner), scaled to this banner and
  // re-aimed so they end exactly on this pill's targets.
  const sx = w / 720;
  const sy = h / 220;
  const scale = (pts: Point[], end: Point): Point[] => {
    const mapped = pts.map(([x, y]) => [cx + (x - 720) * sx, y * sy] as Point);
    mapped[mapped.length - 1] = end;
    const before = mapped[mapped.length - 2] as Point;
    mapped[mapped.length - 2] = [(before[0] + end[0]) / 2, Math.max(end[1] + 10, before[1] * 0.7)];
    return mapped;
  };
  const left = scale(
    [[372, 206], [440, 208], [500, 196], [520, 170], [490, 140], [440, 112], [425, 80], [450, 50], [500, 30], [552, 18]],
    leftBadge,
  );
  const right = scale(
    [[1068, 206], [1000, 208], [945, 196], [925, 170], [960, 135], [1010, 100], [1020, 68], [990, 42], [920, 26], [856, 18]],
    rightEyes,
  );

  return {
    screenW: p.screen.width,
    cx,
    notchRect: { x: notch.x, y: 0, w: Math.max(notch.width, 1), h: notch.height, r: 10 },
    pillRect: { x: pillX, y: 0, w: pillW, h: pill.height, r: pill.radius },
    banner: { w, h },
    eyes,
    leftBadge,
    rightEyes,
    rightText,
    sidePaths: [buildPath(left), buildPath(right)],
    crescents: [
      [[eyes[0] - 13, eyes[1]], [cx - w * 0.17, h * 1.05], leftBadge],
      [[eyes[0] + 13, eyes[1]], [cx + w * 0.17, h * 1.05], rightEyes],
    ],
  };
}
