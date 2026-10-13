// Port of BriefingSections (App/Dayflow/Views/UI/Briefing/BriefingService.swift):
// splits the model's briefing text into the parts the screen shows.

export interface BriefingSections {
  leftOff: string;
  goal: string;
  nextSteps: string[];
  refs: string;
}

type Key = "left" | "goal" | "next" | "refs";

const HEADERS: [string, Key][] = [
  ["WHERE YOU LEFT OFF", "left"],
  ["YOUR GOAL", "goal"],
  ["NEXT STEPS", "next"],
];

/** "(2026-10-12#2)", "[2026-10-12#3]" and "(projects/x.md)" are for the model, not for reading. */
export function stripCitations(text: string): string {
  return text
    .replace(/\s*[([]\d{4}-\d\d-\d\d#\d+[)\]]/g, "")
    .replace(/\s*\((?:memory\/|projects\/)[^)]*\)/g, "")
    .trim();
}

export function parseSections(raw: string): BriefingSections {
  const buffers: Record<Key, string[]> = { left: [], goal: [], next: [], refs: [] };
  let current: Key = "left";

  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    const upper = trimmed.toUpperCase();
    const header = HEADERS.find(([name]) => upper.startsWith(name));
    if (header) {
      current = header[1];
      buffers[current].push(trimmed.slice(header[0].length).replace(/^:/, "").trim());
      continue;
    }
    if (upper.startsWith("REFS:")) {
      current = "refs";
      buffers.refs.push(trimmed.slice(5));
      continue;
    }
    buffers[current].push(trimmed);
  }

  const joined = (key: Key) => buffers[key].join(" ").trim().replace(/ {2,}/g, " ");

  return {
    leftOff: stripCitations(joined("left")),
    goal: stripCitations(joined("goal")),
    refs: joined("refs"),
    nextSteps: buffers.next
      .map((step) => stripCitations(step.replace(/^\s*(\d+[.)]|[-•*])\s*/, "")))
      .filter((step) => step.length > 0),
  };
}

export const isEmptySections = (s: BriefingSections) =>
  s.leftOff === "" && s.goal === "" && s.nextSteps.length === 0;
