// The palette colors are written twice: in Swift (DayframePalette.swift, for native
// surfaces) and here (for the web surfaces). This test reads the Swift file and fails
// as soon as the two disagree, so a color changed on one side can't drift.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { PALETTES, paletteStops } from "./palettes";

const swift = readFileSync(
  resolve(import.meta.dirname, "../../../App/Dayflow/Utilities/DayframePalette.swift"),
  "utf8",
);

/** The `Spec(...)` arguments for one palette case, as field → value(s). */
function swiftSpec(name: string): Record<string, string | string[]> {
  const block = swift.match(new RegExp(`case \\.${name}:\\s*return Spec\\(([^)]*)\\)`))?.[1];
  if (!block) throw new Error(`No Spec for .${name} in DayframePalette.swift`);
  const fields: Record<string, string | string[]> = {};
  for (const [, key, list, single] of block.matchAll(/(\w+): (?:\[([^\]]*)\]|"(\w+)")/g)) {
    fields[key as string] =
      list !== undefined ? [...list.matchAll(/"(\w+)"/g)].map((m) => m[1] as string) : (single as string);
  }
  return fields;
}

describe("palette stops match DayframePalette.swift", () => {
  for (const name of PALETTES.filter((p) => p !== "original")) {
    it(name, () => {
      const s = swiftSpec(name);
      const web = paletteStops(name);
      expect(web.dark).toEqual(s.darkBG);
      expect(web.light).toEqual(s.lightBG);
      expect(web.accent).toBe(s.accent);
      expect(web.accentLight).toBe(s.accentTextLight);
      expect(web.accentDark).toBe(s.accentTextDark);
    });
  }

  it("original (Dayflow's own colors, the fallback in `stops`)", () => {
    const fallback = swift.match(/guard let s = spec else \{\s*return \((.*)\)\s*\}/)?.[1];
    if (!fallback) throw new Error("No Original fallback in DayframePalette.stops");
    const hexes = [...fallback.matchAll(/"(\w+)"/g)].map((m) => m[1]);
    const web = paletteStops("original");
    expect(hexes).toEqual([...web.dark, ...web.light, web.accent, web.accentLight]);
  });
});
