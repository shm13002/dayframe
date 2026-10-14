// The Jarvis tab: one quiet column. Conversation, tool rows, approval cards and a composer,
// in Dayframe's palette. Quick by design: Enter sends, Esc stops, ⌥Space talks.
import { AnimatePresence, motion } from "motion/react";
import { ArrowUp, Check, ChevronDown, CircleStop, Loader2, Mic, Plus, ShieldAlert, Wrench } from "lucide-react";
import { type FormEvent, type KeyboardEvent, useEffect, useRef, useState } from "react";
import { enter, settle } from "@/lib/motion";
import { cn } from "@/lib/utils";
import { CHOICE_LABEL, approvalFacts, toolLabel } from "./approvals";
import type { ChatMessage, ToolMessage } from "./chat-model";
import { postToHost, type JarvisContext } from "./host";
import type { Jarvis, Pending } from "./use-jarvis";

export function JarvisPage({ jarvis, context }: { jarvis: Jarvis; context: JarvisContext }) {
  const [draft, setDraft] = useState("");
  const scroller = useRef<HTMLDivElement>(null);
  const input = useRef<HTMLTextAreaElement>(null);
  const { chat, connection } = jarvis;
  const busy = Boolean(chat?.streaming);
  const online = connection === "open";

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight, behavior: "smooth" });
  }, [chat?.messages.length, chat?.messages.at(-1), jarvis.pending.length]);

  useEffect(() => input.current?.focus(), [chat?.sessionId]);

  const submit = (event?: FormEvent) => {
    event?.preventDefault();
    if (!draft.trim() || !online) return;
    void jarvis.send(draft, "chat");
    setDraft("");
  };

  const onKey = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      submit();
    } else if (event.key === "Escape" && busy) {
      void jarvis.stop();
    }
  };

  return (
    <div className="flex h-full">
      <SessionRail jarvis={jarvis} />
      <main className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center gap-3 px-8 pt-6 pb-3">
          <h1 className="font-serif text-[30px] leading-none text-ink">Jarvis</h1>
          <StatusDot connection={connection} busy={busy} />
          <span className="truncate text-[13px] text-ink-3">{chat?.title || statusLine(context, connection)}</span>
          <div className="ml-auto">
            <BrainPicker jarvis={jarvis} />
          </div>
        </header>

        <div ref={scroller} className="no-scrollbar selectable flex-1 overflow-y-auto px-8 pb-6">
          <div className="mx-auto flex max-w-[720px] flex-col gap-3 pt-2">
            {!chat || chat.messages.length === 0 ? (
              <Welcome context={context} online={online} onPick={(text) => void jarvis.send(text, "chat")} />
            ) : (
              chat.messages.map((message) => <Message key={message.id} message={message} />)
            )}
            {chat?.status && busy ? (
              <p className="flex items-center gap-2 text-[13px] text-ink-3">
                <Loader2 className="size-3.5 animate-spin" aria-hidden />
                {chat.status.text}
              </p>
            ) : null}
            <AnimatePresence>
              {jarvis.pending.map((item) => (
                <PendingCard key={item.request.id} item={item} onAnswer={jarvis.answer} />
              ))}
            </AnimatePresence>
            {jarvis.activeBrain?.limited && chat?.messages.length ? (
              <p className="text-[12px] text-ink-muted">
                Limited mode: Qwen runs on this Mac with a small memory, so tools may not work.
              </p>
            ) : null}
          </div>
        </div>

        <form onSubmit={submit} className="px-8 pb-6">
          <div
            className={cn(
              "mx-auto flex max-w-[720px] items-end gap-2 rounded-[22px] border border-input-border bg-input px-3 py-2",
              "shadow-[0_4px_16px_rgba(0,0,0,0.06)]",
            )}
          >
            <IconButton label="Talk to Jarvis (⌥Space)" onClick={() => postToHost({ type: "listen" })}>
              <Mic className="size-4" aria-hidden />
            </IconButton>
            <textarea
              ref={input}
              rows={1}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={onKey}
              placeholder={online ? "Ask Jarvis to do something…" : "Waiting for Hermes…"}
              className="selectable max-h-40 min-h-[36px] flex-1 resize-none bg-transparent py-2 text-[15px] text-ink outline-none placeholder:text-ink-muted"
            />
            {busy ? (
              <IconButton label="Stop (Esc)" onClick={() => void jarvis.stop()}>
                <CircleStop className="size-4" aria-hidden />
              </IconButton>
            ) : (
              <IconButton label="Send (Enter)" prominent disabled={!draft.trim() || !online} type="submit">
                <ArrowUp className="size-4" aria-hidden />
              </IconButton>
            )}
          </div>
        </form>
      </main>
    </div>
  );
}

function statusLine(context: JarvisContext, connection: string): string {
  if (context.backendNote) return context.backendNote;
  if (!context.port) return "Starting Hermes…";
  if (connection === "open") return "Ready";
  if (connection === "error" || connection === "closed") return "Lost Hermes, reconnecting…";
  return "Connecting…";
}

function StatusDot({ connection, busy }: { connection: string; busy: boolean }) {
  const color = connection === "open" ? (busy ? "bg-accent" : "bg-[#3BB273]") : "bg-ink-muted";
  return (
    <span className="relative flex size-2.5" aria-hidden>
      {busy ? <span className="absolute inset-0 animate-ping rounded-full bg-accent opacity-60" /> : null}
      <span className={cn("relative size-2.5 rounded-full", color)} />
    </span>
  );
}

function SessionRail({ jarvis }: { jarvis: Jarvis }) {
  return (
    <aside className="no-scrollbar flex w-[220px] shrink-0 flex-col gap-1 overflow-y-auto border-r border-shell-border/60 px-3 pt-6 pb-4">
      <button
        type="button"
        onClick={jarvis.newChat}
        className="mb-2 flex items-center gap-2 rounded-chip border border-control-border bg-control px-3 py-2 text-[13px] font-semibold text-control-text hover:brightness-[1.03]"
      >
        <Plus className="size-4" aria-hidden /> New conversation
      </button>
      {jarvis.sessions.map((session) => (
        <button
          key={session.id}
          type="button"
          onClick={() => void jarvis.openSession(session.id)}
          className={cn(
            "truncate rounded-chip px-3 py-1.5 text-left text-[13px] text-ink-2 hover:bg-soft",
            jarvis.chat?.sessionId === session.id && "bg-soft font-semibold text-ink",
          )}
          title={session.preview ?? session.title}
        >
          {session.title || session.preview || "Untitled"}
        </button>
      ))}
    </aside>
  );
}

function BrainPicker({ jarvis }: { jarvis: Jarvis }) {
  const [open, setOpen] = useState(false);
  const active = jarvis.activeBrain;
  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1.5 rounded-full border border-control-border bg-control px-3 py-1.5 text-[12px] font-semibold text-control-text"
      >
        {active ? active.label : "No brain signed in"}
        <ChevronDown className="size-3.5" aria-hidden />
      </button>
      <AnimatePresence>
        {open ? (
          <motion.div
            {...enter}
            className="absolute right-0 z-10 mt-2 w-[230px] rounded-card border border-popover-border bg-popover p-1.5 shadow-lg"
          >
            {jarvis.brains.map((brain) => (
              <button
                key={brain.id}
                type="button"
                onClick={() => {
                  jarvis.chooseBrain(brain.id);
                  setOpen(false);
                }}
                className="flex w-full items-center gap-2 rounded-chip px-2.5 py-2 text-left text-[13px] text-ink hover:bg-soft"
              >
                <span className="flex-1">
                  {brain.label}
                  <span className="block text-[11px] text-ink-3">{brain.model}</span>
                </span>
                {active?.id === brain.id ? <Check className="size-4 text-accent" aria-hidden /> : null}
              </button>
            ))}
            <p className="px-2.5 pt-1.5 pb-1 text-[11px] leading-snug text-ink-muted">
              Applies to new conversations. Sign in to more in Settings › Jarvis.
            </p>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}

const SUGGESTIONS = [
  "What did I work on this morning?",
  "What's using the most memory right now?",
  "How much disk space do I have left?",
  "Find the PDFs I downloaded this week",
];

function Welcome({
  context,
  online,
  onPick,
}: {
  context: JarvisContext;
  online: boolean;
  onPick: (t: string) => void;
}) {
  return (
    <motion.div {...enter} className="flex flex-col gap-4 pt-[12vh]">
      <p className="font-serif text-[34px] leading-tight text-ink">What should we get done?</p>
      <p className="max-w-[520px] text-[14px] leading-relaxed text-ink-2">
        {online
          ? "Jarvis can find and organise files, open apps, check on your Mac and read your timeline. Anything that changes something asks you first."
          : (context.backendNote ?? "Hermes is starting. This takes a few seconds.")}
      </p>
      <div className="flex flex-wrap gap-2">
        {SUGGESTIONS.map((text) => (
          <button
            key={text}
            type="button"
            disabled={!online}
            onClick={() => onPick(text)}
            className="rounded-full border border-control-border bg-control px-3.5 py-2 text-[13px] text-control-text hover:brightness-[1.03] disabled:opacity-50"
          >
            {text}
          </button>
        ))}
      </div>
    </motion.div>
  );
}

function Message({ message }: { message: ChatMessage }) {
  if (message.role === "user") {
    return (
      <motion.div {...enter} className="ml-auto max-w-[80%] rounded-[18px] bg-soft px-4 py-2.5 text-[15px] text-ink">
        <Text text={message.text} />
      </motion.div>
    );
  }
  if (message.role === "tool") return <ToolRow tool={message} />;
  if (message.role === "system") {
    return (
      <p className={cn("text-[13px]", message.level === "error" ? "text-danger" : "text-ink-3")}>{message.text}</p>
    );
  }
  if (!message.text && message.streaming) {
    return (
      <div className="h-5 w-24 overflow-hidden rounded bg-stat">
        <div className="df-sheen h-full w-full" />
      </div>
    );
  }
  return (
    <motion.div {...enter} className="max-w-[92%] text-[15px] leading-relaxed text-ink">
      <Text text={message.text} />
      {message.status === "interrupted" ? <span className="text-[12px] text-ink-muted"> (stopped)</span> : null}
    </motion.div>
  );
}

function ToolRow({ tool }: { tool: ToolMessage }) {
  const [open, setOpen] = useState(false);
  const detail = tool.summary || tool.context || "";
  return (
    <div className="rounded-chip border border-card-border/60 bg-stat px-3 py-2 text-[13px] text-ink-2">
      <button type="button" onClick={() => setOpen((v) => !v)} className="flex w-full items-center gap-2 text-left">
        {tool.running ? (
          <Loader2 className="size-3.5 animate-spin text-accent" aria-hidden />
        ) : (
          <Wrench className="size-3.5 text-ink-3" aria-hidden />
        )}
        <span className="font-semibold text-ink">{toolLabel(tool.name)}</span>
        {detail ? <span className="truncate text-ink-3">{detail}</span> : null}
        {tool.durationS ? <span className="ml-auto shrink-0 text-ink-muted">{tool.durationS.toFixed(1)}s</span> : null}
      </button>
      {open && tool.resultText ? (
        <pre className="selectable mt-2 max-h-56 overflow-auto rounded bg-card p-2 font-mono text-[11.5px] whitespace-pre-wrap text-ink-2">
          {tool.resultText.slice(0, 6000)}
        </pre>
      ) : null}
    </div>
  );
}

function PendingCard({ item, onAnswer }: { item: Pending; onAnswer: Jarvis["answer"] }) {
  const [answers, setAnswers] = useState<Record<string, string>>({});
  if (item.kind === "clarify") {
    const questions = item.params.questions ?? [];
    const complete = questions.every((q) => answers[q.qid]?.trim());
    return (
      <motion.div {...enter} layout transition={settle} className="rounded-card border border-accent/40 bg-card p-4">
        {questions.map((q) => (
          <div key={q.qid} className="mb-3 last:mb-0">
            <p className="text-[14px] font-semibold text-ink">{q.question}</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {(q.choices ?? []).map((choice) => (
                <button
                  key={choice}
                  type="button"
                  onClick={() => setAnswers((all) => ({ ...all, [q.qid]: choice }))}
                  className={cn(
                    "rounded-full border px-3 py-1.5 text-[13px]",
                    answers[q.qid] === choice
                      ? "border-button-border bg-button text-button-text"
                      : "border-control-border bg-control text-control-text",
                  )}
                >
                  {choice}
                </button>
              ))}
            </div>
            <input
              value={(q.choices ?? []).includes(answers[q.qid] ?? "") ? "" : (answers[q.qid] ?? "")}
              onChange={(e) => setAnswers((all) => ({ ...all, [q.qid]: e.target.value }))}
              placeholder={q.choices?.length ? "Or type an answer" : "Your answer"}
              className="selectable mt-2 w-full rounded-chip border border-input-border bg-input px-3 py-1.5 text-[13px] text-ink outline-none"
            />
          </div>
        ))}
        <div className="mt-3 flex gap-2">
          <button
            type="button"
            disabled={!complete}
            onClick={() => onAnswer(item, { answers })}
            className="rounded-full border border-button-border bg-button px-3.5 py-1.5 text-[13px] font-semibold text-button-text disabled:opacity-40"
          >
            Answer
          </button>
          <button
            type="button"
            onClick={() => onAnswer(item, {})}
            className="rounded-full border border-control-border bg-control px-3.5 py-1.5 text-[13px] text-control-text"
          >
            Skip
          </button>
        </div>
      </motion.div>
    );
  }
  const facts = approvalFacts(item.params);
  return (
    <motion.div
      {...enter}
      layout
      transition={settle}
      className={cn("rounded-card border bg-card p-4", facts.destructive ? "border-danger/50" : "border-accent/40")}
    >
      <div className="flex items-start gap-2.5">
        <ShieldAlert
          className={cn("mt-0.5 size-4 shrink-0", facts.destructive ? "text-danger" : "text-accent")}
          aria-hidden
        />
        <div className="min-w-0">
          <p className="text-[14px] font-semibold text-ink">
            {facts.destructive ? "Jarvis wants to do something that can't be undone" : "Jarvis is asking first"}
          </p>
          <p className="selectable mt-1 text-[13px] leading-snug text-ink-2">
            {item.params.description || item.params.command || facts.toolName}
          </p>
        </div>
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {facts.choices.map((choice) => (
          <button
            key={choice}
            type="button"
            onClick={() => onAnswer(item, { choice })}
            className={cn(
              "rounded-full border px-3.5 py-1.5 text-[13px] font-semibold",
              choice === "deny"
                ? "border-control-border bg-control text-control-text"
                : "border-button-border bg-button text-button-text",
            )}
          >
            {CHOICE_LABEL[choice]}
          </button>
        ))}
      </div>
    </motion.div>
  );
}

function IconButton({
  children,
  label,
  onClick,
  prominent,
  disabled,
  type = "button",
}: {
  children: React.ReactNode;
  label: string;
  onClick?: () => void;
  prominent?: boolean;
  disabled?: boolean;
  type?: "button" | "submit";
}) {
  return (
    <button
      type={type}
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "grid size-9 shrink-0 place-items-center rounded-full border transition-[filter,opacity] disabled:opacity-40",
        prominent ? "border-button-border bg-button text-button-text" : "border-transparent text-ink-2 hover:bg-soft",
      )}
    >
      {children}
    </button>
  );
}

/** Light formatting: paragraphs, **bold**, `code` and fenced code blocks. No HTML from the model. */
function Text({ text }: { text: string }) {
  const blocks = text.split(/```[a-z]*\n?/);
  return (
    <>
      {blocks.map((block, i) =>
        i % 2 === 1 ? (
          <pre key={i} className="my-2 overflow-x-auto rounded-chip bg-stat p-3 font-mono text-[12.5px] text-ink">
            {block.replace(/\n$/, "")}
          </pre>
        ) : (
          block
            .split(/\n{2,}/)
            .filter((p) => p.trim())
            .map((para, j) => (
              <p key={`${i}-${j}`} className="my-1.5 whitespace-pre-wrap first:mt-0 last:mb-0">
                {inline(para)}
              </p>
            ))
        ),
      )}
    </>
  );
}

function inline(text: string) {
  return text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g).map((part, i) =>
    part.startsWith("**") && part.endsWith("**") ? (
      <strong key={i}>{part.slice(2, -2)}</strong>
    ) : part.startsWith("`") && part.endsWith("`") ? (
      <code key={i} className="rounded bg-stat px-1 font-mono text-[0.9em]">
        {part.slice(1, -1)}
      </code>
    ) : (
      part
    ),
  );
}
