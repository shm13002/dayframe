// The island's pure building blocks: easing, paths, the spring, minute labels, and the
// beat sheets every show runs on.
import { describe, expect, it } from "vitest";
import { buildPath, ease, formatMinutes, pointAt, smooth, springStep } from "./math";
import { TIMELINES } from "./timelines";

describe("easing", () => {
  it("smooth and ease run from 0 to 1 and clamp outside their range", () => {
    expect(smooth(1, 2, 0)).toBe(0);
    expect(smooth(1, 2, 1.5)).toBe(0.5);
    expect(smooth(1, 2, 3)).toBe(1);
    expect(ease(-1)).toBe(0);
    expect(ease(0.5)).toBe(0.5);
    expect(ease(2)).toBe(1);
  });
});

describe("paths", () => {
  const line = buildPath([
    [0, 0],
    [100, 0],
  ]);

  it("measures a straight line by its length", () => {
    expect(line.len).toBeCloseTo(100);
  });

  it("finds the midpoint and a unit normal at right angles to the line", () => {
    const [x, y, nx, ny] = pointAt(line, 0.5);
    expect(x).toBeCloseTo(50);
    expect(y).toBeCloseTo(0);
    expect(Math.hypot(nx, ny)).toBeCloseTo(1);
    expect(nx).toBeCloseTo(0);
  });
});

describe("spring", () => {
  it("settles on its target within a second at 60 fps", () => {
    let [x, v] = [0, 0];
    for (let i = 0; i < 60; i++) [x, v] = springStep(x, v, 1, 1 / 60);
    expect(x).toBeCloseTo(1, 2);
  });
});

describe("minute labels", () => {
  it("reads like the app's tracked-time text", () => {
    expect(formatMinutes(0)).toBe("0m");
    expect(formatMinutes(42.4)).toBe("42m");
    expect(formatMinutes(199)).toBe("3h 19m");
    expect(formatMinutes(-5)).toBe("0m");
  });
});

describe("beat sheets", () => {
  for (const [name, t] of Object.entries(TIMELINES)) {
    it(`${name}: every beat and sound lands before the show is done`, () => {
      expect(t.collapseAt).toBeLessThan(t.doneAt);
      expect(t.textOutAt).toBeLessThanOrEqual(t.collapseAt);
      expect(t.streams[0]).toBeLessThanOrEqual(t.streams[1]);
      expect(t.streams[1]).toBeLessThanOrEqual(t.streams[2]);
      for (const [at] of t.cues) expect(at).toBeLessThan(t.doneAt);
      const times = t.cues.map(([at]) => at);
      expect(times).toEqual([...times].sort((a, b) => a - b));
    });
  }
});
