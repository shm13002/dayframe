import { describe, expect, it } from "vitest";
import { approvalFacts } from "./approvals";
import { brainFor } from "./brains";
import { appendUser, emptyChat, lastAnswer, reduceChatEvent, type ChatState } from "./chat-model";
import type { GatewayEvent } from "./hermes/upstream/gateway-events";

const ev = (type: string, payload?: unknown): GatewayEvent =>
  ({ type, session_id: "s1", payload }) as unknown as GatewayEvent;

const run = (state: ChatState, ...events: GatewayEvent[]) => events.reduce(reduceChatEvent, state);

describe("chat model", () => {
  it("streams text, seals it at a tool call and opens a new bubble after", () => {
    const state = run(
      appendUser(emptyChat("s1"), "what is using memory?"),
      ev("message.start"),
      ev("message.delta", { text: "Let me check." }),
      ev("tool.start", { tool_id: "t1", name: "system_processes", args: { sort: "memory" } }),
      ev("tool.complete", { tool_id: "t1", name: "system_processes", summary: "12 processes" }),
      ev("message.delta", { text: "Chrome uses 5 GB." }),
      ev("message.complete", { text: "Chrome uses 5 GB.", status: "complete" }),
    );
    expect(state.messages.map((m) => m.role)).toEqual(["user", "assistant", "tool", "assistant"]);
    expect(state.streaming).toBe(false);
    const tool = state.messages[2];
    expect(tool?.role === "tool" && !tool.running && tool.summary).toBe("12 processes");
    expect(lastAnswer(state)).toBe("Chrome uses 5 GB.");
  });

  it("uses the final text when nothing streamed, and shows errors", () => {
    const answered = run(emptyChat("s1"), ev("message.complete", { text: "Done.", status: "complete" }));
    expect(lastAnswer(answered)).toBe("Done.");
    const failed = run(emptyChat("s1"), ev("message.complete", { text: "", status: "error", error: "rate limited" }));
    expect(failed.messages.at(-1)).toMatchObject({ role: "system", level: "error", text: "rate limited" });
  });

  it("has no answer to speak while the newest message is the owner's", () => {
    const state = appendUser(run(emptyChat("s1"), ev("message.complete", { text: "Hi." })), "next");
    expect(lastAnswer(state)).toBe("");
  });
});

describe("approvals", () => {
  it("never offers session or always for destructive system tools", () => {
    expect(
      approvalFacts({
        command: "<system_files> (plugin approval rule)",
        description: "Trash 3 files",
        choices: ["once", "session", "always", "deny"],
      }),
    ).toEqual({ toolName: "system_files", destructive: true, choices: ["once", "deny"] });
    expect(
      approvalFacts({
        command: "<system_files> (plugin approval rule)",
        description: "Move a.pdf to Documents",
        choices: ["once", "session", "always", "deny"],
      }).choices,
    ).toEqual(["once", "session", "always", "deny"]);
  });
});

describe("brains", () => {
  it("names the brain behind a provider", () => {
    expect(brainFor("xai-oauth", "grok-4")?.id).toBe("grok");
    expect(brainFor("custom", "qwen3.5:4b")?.limited).toBe(true);
    expect(brainFor("openai-codex", "gpt-5")?.id).toBe("chatgpt");
    expect(brainFor("mystery", "x")).toBeNull();
  });
});
