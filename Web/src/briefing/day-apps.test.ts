import { describe, expect, it } from "vitest";
import { parseDayApps } from "./day-apps";

const icon = "data:image/png;base64,iVBORw0KGgo=";

describe("parseDayApps", () => {
  it("keeps well-formed apps in order", () => {
    expect(
      parseDayApps([
        { id: "com.apple.Safari", name: "Safari", icon },
        { id: "com.todesktop.230313mzl4w4u92", name: " Cursor ", icon },
      ]),
    ).toEqual([
      { id: "com.apple.Safari", name: "Safari", icon },
      { id: "com.todesktop.230313mzl4w4u92", name: "Cursor", icon },
    ]);
  });

  it("drops anything that isn't a bundle ID, a name and a PNG data URL", () => {
    expect(
      parseDayApps([
        { id: "com.apple.Safari", name: "Safari", icon: "https://example.com/x.png" },
        { id: "rm -rf ~", name: "Bad", icon },
        { id: "com.apple.Notes", name: "", icon },
        { id: "com.apple.Mail", name: "Mail", icon: "data:image/svg+xml;base64,PHN2Zz4=" },
        null,
        "com.apple.Safari",
      ]),
    ).toEqual([]);
  });

  it("treats a missing or wrong-shaped list as no apps", () => {
    expect(parseDayApps(undefined)).toEqual([]);
    expect(parseDayApps({ id: "x" })).toEqual([]);
  });
});
