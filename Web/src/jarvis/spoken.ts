// What Jarvis says out loud after a voice turn: one short summary sentence, spoken the moment it
// has streamed in (the owner's choice, 2026-10-14). The model is asked for it through Hermes's
// voice_context, so there is no second model call; the full answer appears on screen as usual.

export const VOICE_CONTEXT =
  "This request was spoken aloud by Shahzeb. Begin your reply with ONE short sentence (at most 18 words) " +
  "that says the result or what you are doing, in plain words: no markdown, lists, URLs or file paths. " +
  "That sentence is read aloud. Put any details after it.";

const clean = (text: string) =>
  text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/https?:\/\/\S+/g, "")
    .replace(/[*_`#>|"]+/g, "")
    .replace(/\s+/g, " ")
    .trim();

/**
 * The first sentence of a streaming answer once it is complete, or null while it is still being
 * written. When the answer is finished (`done`), whatever is there counts. Capped at 160 chars.
 */
export function firstSpokenSentence(text: string, done: boolean): string | null {
  const plain = clean(text);
  if (!plain) return null;
  const match = plain.match(/^.*?[.!?](?=\s|$)/);
  const sentence = match && (done || plain.length > match[0].length) ? match[0] : done ? plain : null;
  if (!sentence) return plain.length > 200 ? `${plain.slice(0, plain.lastIndexOf(" ", 157))}…` : null;
  return sentence.length > 160 ? `${sentence.slice(0, sentence.lastIndexOf(" ", 157))}…` : sentence;
}
