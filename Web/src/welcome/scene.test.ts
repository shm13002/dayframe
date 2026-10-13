// The welcome's choreography, checked against the Aether Pulse cue sheet: ignition at
// 2.6 s, locks at 3.42 / 3.55 / 3.68 s, the wordmark from 3.95 s, gone by 5.4 s.
import { describe, expect, it } from "vitest";
import { DURATION, frameAt, REDUCED_DURATION } from "./scene";

describe("first launch", () => {
  const at = (T: number) => frameAt("firstLaunch", T, false);

  it("starts dark and has fully dissolved by the time it reports done", () => {
    expect(at(0).stage).toBe(0);
    expect(at(DURATION.firstLaunch).stage).toBe(0);
  });

  it("ignites at 2.6 s: no eclipse before, a flash and an eclipse after", () => {
    expect(at(2.5).eclipse.alpha).toBe(0);
    expect(at(2.5).flash).toBe(0);
    expect(at(2.7).eclipse.alpha).toBeGreaterThan(0.9);
    expect(at(2.62).flash).toBeGreaterThan(0.8);
  });

  it("fires the three locks in order", () => {
    expect(at(3.4).locks).toEqual([0, 0, 0]);
    expect(at(3.45).locks[0]).toBeGreaterThan(0);
    expect(at(3.45).locks[1]).toBe(0);
    expect(at(3.6).locks[1]).toBeGreaterThan(0);
    expect(at(3.6).locks[2]).toBe(0);
    expect(at(3.7).locks[2]).toBeGreaterThan(0);
  });

  it("shows the wordmark only after the locks and before the dissolve", () => {
    expect(at(3.7).word).toBe(0);
    expect(at(4.5).word).toBe(1);
    expect(at(5.2).word).toBe(0);
  });

  it("is a pure function of time", () => {
    expect(at(3.123)).toEqual(at(3.123));
  });
});

describe("daily wake", () => {
  const at = (T: number) => frameAt("dailyWake", T, false);

  it("lasts two seconds and never shows the wordmark", () => {
    expect(DURATION.dailyWake).toBe(2);
    expect(at(DURATION.dailyWake).stage).toBe(0);
    for (const T of [0.5, 1, 1.5]) expect(at(T).word).toBe(0);
  });
});

describe("reduce motion", () => {
  it("holds still and fades out by its shorter end", () => {
    const early = frameAt("firstLaunch", 0.3, true);
    const later = frameAt("firstLaunch", 0.5, true);
    expect(early.vortex.spin).toBe(0);
    expect(later.eclipse).toEqual(early.eclipse);
    expect(frameAt("firstLaunch", REDUCED_DURATION, true).stage).toBe(0);
  });
});
