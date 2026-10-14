import { describe, expect, it } from "vitest";
import { firstSpokenSentence } from "./spoken";

describe("first spoken sentence", () => {
  it("waits until the first sentence is complete", () => {
    expect(firstSpokenSentence("Chrome is using", false)).toBeNull();
    expect(firstSpokenSentence("Chrome is using the most memory.", false)).toBeNull();
    expect(firstSpokenSentence("Chrome is using the most memory. Next", false)).toBe(
      "Chrome is using the most memory.",
    );
  });

  it("takes what is there when the answer is done, cleaned for speech", () => {
    expect(firstSpokenSentence("**Done**, I moved [3 files](file:///a)", true)).toBe("Done, I moved 3 files");
    expect(firstSpokenSentence("Version 1.4 is ready. Details below.", false)).toBe("Version 1.4 is ready.");
  });

  it("never waits forever on a run-on sentence", () => {
    const long = "word ".repeat(60);
    const line = firstSpokenSentence(long, false);
    expect(line).not.toBeNull();
    expect(line!.length).toBeLessThanOrEqual(161);
  });
});
