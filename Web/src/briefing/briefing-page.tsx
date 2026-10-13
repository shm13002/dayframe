import {
  ArrowUp,
  Ellipsis,
  RotateCw,
  Search,
  Sparkles,
  Sunrise,
  Target,
  ThumbsDown,
  ThumbsUp,
  Undo2,
} from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type FormEvent, useMemo, useState } from "react";
import { ActivityChip } from "@/components/dayframe/activity-chip";
import { CardTitle, GlassCard } from "@/components/dayframe/card";
import { InkText } from "@/components/dayframe/ink-text";
import { Menu, type MenuSection } from "@/components/dayframe/menu";
import { PillButton } from "@/components/dayframe/pill-button";
import { SkeletonParagraph } from "@/components/dayframe/skeleton";
import { Stat } from "@/components/dayframe/stat";
import { TodoRow } from "@/components/dayframe/todo-row";
import { BlurFade } from "@/components/ui/blur-fade";
import { NumberTicker } from "@/components/ui/number-ticker";
import { type CategoryColor, isEmbedded, postToHost } from "@/lib/bridge";
import { duration, ease, settle, stagger } from "@/lib/motion";
import { useMediaQuery } from "@/lib/use-media-query";
import { formatMinutes, greeting } from "@/lib/utils";
import type { TimelineCard } from "./api";
import type { DayApp } from "./day-apps";
import { isEmptySections, parseSections, stripCitations } from "./sections";
import type { Briefing } from "./use-briefing";

const WRITERS: { id: string; label: string }[] = [
  { id: "ollama", label: "Qwen (on this Mac)" },
  { id: "claude_cli", label: "Claude" },
  { id: "codex_cli", label: "ChatGPT" },
  { id: "grok_cli", label: "Grok" },
];

const MORE_PAGES: { id: string; label: string }[] = [
  { id: "memory", label: "Memory" },
  { id: "projects", label: "Projects" },
  { id: "weekly", label: "Weekly report" },
  { id: "automations", label: "Automations" },
  { id: "settings", label: "Briefing settings" },
];

const writerName = (id: string) =>
  id === "openai" ? "LM Studio" : (WRITERS.find((w) => w.id === id)?.label ?? "Qwen (on this Mac)");

const timeFormat = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" });
const hourFormat = new Intl.DateTimeFormat(undefined, { hour: "numeric" });
const dateFormat = new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" });

function cardTime(card: TimelineCard): string {
  const start = timeFormat.format(new Date(card.startTs * 1000));
  return card.endTs ? `${start} – ${timeFormat.format(new Date(card.endTs * 1000))}` : start;
}

function hourLabel(hour: number): string {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  return hourFormat.format(d);
}

function openMore(page: string) {
  if (!postToHost({ type: "openMore", page })) window.open(`/#/${page}`, "_blank", "noopener");
}

interface BriefingPageProps {
  briefing: Briefing;
  categories: CategoryColor[];
  dayApps: DayApp[];
}

export function BriefingPage({ briefing, categories, dayApps }: BriefingPageProps) {
  const { state } = briefing;
  const wide = useMediaQuery("(min-width: 900px)");
  const sections = useMemo(() => parseSections(state?.briefing ?? ""), [state?.briefing]);

  const colorFor = (category?: string) =>
    categories.find((c) => c.name.localeCompare(category ?? "", undefined, { sensitivity: "accent" }) === 0)?.color ??
    "var(--df-accent)";

  // One orchestrated entrance: the cards settle in order, once.
  let order = 0;
  const enterAt = () => order++ * stagger;

  const hero = (
    <BlurFade delay={enterAt()} key="hero">
      <HeroCard briefing={briefing} sections={sections} />
    </BlurFade>
  );
  const next = (
    <BlurFade delay={enterAt()} key="next">
      <NextThingCard
        step={sections.nextSteps[0]}
        goal={state?.sessionGoal || sections.goal || undefined}
        writing={briefing.writing}
      />
    </BlurFade>
  );
  const loops = (
    <BlurFade delay={enterAt()} key="loops">
      <LoopsCard briefing={briefing} />
    </BlurFade>
  );
  const today = (
    <BlurFade delay={enterAt()} key="today">
      <TodayCard cards={state?.timeline ?? []} colorFor={colorFor} />
    </BlurFade>
  );
  const week = (
    <BlurFade delay={enterAt()} key="week">
      <WeekCard briefing={briefing} colorFor={colorFor} />
    </BlurFade>
  );

  return (
    <main className="no-scrollbar h-full overflow-y-auto">
      <div className="mx-auto flex max-w-[1240px] flex-col gap-[22px] px-6 pt-7 pb-10 min-[900px]:px-11">
        <Header briefing={briefing} />
        <ErrorNotice error={briefing.error} onRetry={briefing.refresh} onDismiss={briefing.dismissError} />
        {isEmbedded && dayApps.length > 0 ? (
          <BlurFade delay={enterAt()}>
            <TodaysApps apps={dayApps} />
          </BlurFade>
        ) : null}

        {/* Wide: the story on the left, what to do now on the right. Narrow: one column by priority. */}
        {wide ? (
          <div className="grid grid-cols-[minmax(0,1fr)_min(360px,34%)] items-start gap-[18px]">
            <div className="flex min-w-0 flex-col gap-[18px]">
              {hero}
              {today}
            </div>
            <div className="flex min-w-0 flex-col gap-[18px]">
              {next}
              {loops}
              {week}
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-[18px]">
            {hero}
            {next}
            {loops}
            {today}
            {week}
          </div>
        )}

        <BlurFade delay={enterAt()}>
          <AskCard briefing={briefing} />
        </BlurFade>
      </div>
    </main>
  );
}

function Header({ briefing }: { briefing: Briefing }) {
  const { state, writing } = briefing;
  const writer = state?.writer ?? "ollama";
  const written = state?.briefingAt ? timeFormat.format(new Date(state.briefingAt * 1000)) : null;

  const sections: MenuSection[] = [
    {
      title: "Open",
      items: MORE_PAGES.map((p) => ({ id: p.id, label: p.label, onSelect: () => openMore(p.id) })),
    },
    {
      title: "Briefings are written by",
      items: WRITERS.map((w) => ({
        id: w.id,
        label: w.label,
        checked: writer === w.id,
        onSelect: () => void briefing.setWriter(w.id),
      })),
    },
  ];

  return (
    <header className="relative z-30 flex flex-wrap items-end gap-x-3.5 gap-y-3">
      <div className="mr-auto flex min-w-0 flex-col gap-1">
        <h1 className="font-serif text-[30px] leading-none font-normal text-ink">{dateFormat.format(new Date())}</h1>
        <p className="text-[13px] text-ink-2">
          {greeting()}.{" "}
          {written
            ? `${writerName(writer)} wrote this briefing at ${written}.`
            : `Briefings are written by ${writerName(writer)}.`}
        </p>
      </div>
      <PillButton prominent icon={Sparkles} busy={writing} onClick={() => void briefing.newBriefing()}>
        {writing ? "Writing…" : "New briefing"}
      </PillButton>
      <Menu label="More" trigger={<Ellipsis className="size-4" strokeWidth={2.4} aria-hidden />} sections={sections} />
    </header>
  );
}

function ErrorNotice({
  error,
  onRetry,
  onDismiss,
}: {
  error: string | null;
  onRetry: () => void;
  onDismiss: () => void;
}) {
  return (
    <AnimatePresence initial={false}>
      {error ? (
        <motion.div
          role="alert"
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: "auto" }}
          exit={{ opacity: 0, height: 0 }}
          transition={{ duration: duration.base, ease: ease.outQuart }}
          className="overflow-hidden"
        >
          <div className="flex items-center gap-3 rounded-chip border border-danger/40 bg-danger/10 px-4 py-2.5 text-[13px] text-ink">
            <span className="mr-auto">{error}</span>
            <PillButton icon={RotateCw} onClick={onRetry}>
              Try again
            </PillButton>
            <button type="button" onClick={onDismiss} className="text-[12px] text-ink-muted hover:text-ink-2">
              Dismiss
            </button>
          </div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}

function HeroCard({ briefing, sections }: { briefing: Briefing; sections: ReturnType<typeof parseSections> }) {
  const [thumbs, setThumbs] = useState<boolean | null>(null);
  const empty = isEmptySections(sections);

  return (
    <GlassCard aria-label="Where you left off" aria-busy={briefing.writing}>
      <div className="flex flex-col gap-4">
        <CardTitle>Where you left off</CardTitle>
        {briefing.writing ? (
          <SkeletonParagraph lines={4} />
        ) : empty ? (
          <p className="text-[15px] text-ink-2">
            No briefing yet. Choose New briefing, or keep working and one appears when you come back.
          </p>
        ) : (
          <>
            <p className="max-w-[68ch] text-[17px] leading-[1.6] text-ink">
              <InkText key={briefing.briefingVersion} text={sections.leftOff} />
            </p>
            {sections.nextSteps.length > 1 ? (
              <div className="flex flex-col gap-2.5">
                <p className="text-[12px] font-semibold text-ink-muted">Then</p>
                <ol className="flex flex-col gap-2.5">
                  {sections.nextSteps.slice(1).map((step, i) => (
                    <li key={`${briefing.briefingVersion}-${i}`} className="flex items-baseline gap-2.5">
                      <span
                        aria-hidden
                        className="grid size-5 shrink-0 place-items-center rounded-full bg-soft text-[12px] font-bold text-accent"
                      >
                        {i + 2}
                      </span>
                      <span className="selectable text-[14px] leading-snug text-ink-2">{step}</span>
                    </li>
                  ))}
                </ol>
              </div>
            ) : null}
            <div className="flex items-center gap-2.5">
              <PillButton icon={Undo2} onClick={() => void briefing.resume()}>
                Resume my apps
              </PillButton>
              <div className="ml-auto flex items-center gap-1.5 text-[12px] text-ink-muted">
                <span aria-live="polite">{thumbs === null ? "Useful?" : "Thanks"}</span>
                {([true, false] as const).map((up) => {
                  const Icon = up ? ThumbsUp : ThumbsDown;
                  return (
                    <button
                      key={String(up)}
                      type="button"
                      aria-label={up ? "Useful" : "Not useful"}
                      aria-pressed={thumbs === up}
                      onClick={() => {
                        setThumbs(up);
                        void briefing.feedback(up);
                      }}
                      className={thumbs === up ? "text-accent" : "hover:text-ink-2"}
                    >
                      <Icon className="size-3.5" fill={thumbs === up ? "currentColor" : "none"} aria-hidden />
                    </button>
                  );
                })}
              </div>
            </div>
          </>
        )}
      </div>
    </GlassCard>
  );
}

/** The apps from Settings › Start of day: one click brings each forward, or sets up the whole day. */
function TodaysApps({ apps }: { apps: DayApp[] }) {
  return (
    <section aria-label="Today's apps" className="flex flex-wrap items-center gap-x-4 gap-y-3">
      <h2 className="font-serif text-[20px] leading-tight text-shell-heading">Today's apps</h2>
      <ul className="flex flex-wrap items-center gap-2.5">
        {apps.map((app, i) => (
          <motion.li
            key={app.id}
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: duration.quick, ease: ease.outQuart, delay: i * 0.04 }}
          >
            <button
              type="button"
              title={`Open ${app.name}`}
              aria-label={`Open ${app.name}`}
              onClick={() => postToHost({ type: "openApp", id: app.id })}
              className="grid size-11 place-items-center rounded-[12px] transition-transform duration-150 hover:-translate-y-0.5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent active:translate-y-0"
            >
              <img src={app.icon} alt="" className="size-10" draggable={false} />
            </button>
          </motion.li>
        ))}
      </ul>
      <PillButton icon={Sunrise} onClick={() => postToHost({ type: "setUpDay" })}>
        Set up my day
      </PillButton>
    </section>
  );
}

function NextThingCard({ step, goal, writing }: { step?: string; goal?: string; writing: boolean }) {
  return (
    <GlassCard tint aria-label="Your next thing">
      <div className="flex flex-col gap-3.5">
        <CardTitle>Your next thing</CardTitle>
        {writing ? (
          <SkeletonParagraph lines={2} />
        ) : (
          <p className="selectable font-serif text-[24px] leading-[1.25] text-ink">
            {step ?? "Pick one small step and start."}
          </p>
        )}
        {goal ? (
          <span className="inline-flex max-w-full items-center gap-2 self-start rounded-full border border-control-border bg-control px-3 py-1.5 text-[13px] font-medium text-control-text shadow-[inset_0_0_4px_var(--df-control-glow)]">
            <Target className="size-3.5 shrink-0" aria-hidden />
            <span className="line-clamp-2">{stripCitations(goal)}</span>
          </span>
        ) : null}
      </div>
    </GlassCard>
  );
}

function LoopsCard({ briefing }: { briefing: Briefing }) {
  const [draft, setDraft] = useState("");
  const todos = (briefing.state?.todos ?? []).filter((t) => !t.done);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    briefing.addTodo(draft);
    setDraft("");
  };

  return (
    <GlassCard aria-label="Open loops">
      <div className="flex flex-col gap-3">
        <CardTitle
          trailing={
            todos.length > 0 ? (
              <span className="text-[12px] font-bold text-accent tabular-nums" aria-label={`${todos.length} open`}>
                {todos.length}
              </span>
            ) : null
          }
        >
          Open loops
        </CardTitle>
        {todos.length === 0 ? <p className="text-[14px] text-ink-muted">All clear. Nothing open right now.</p> : null}
        <ul className="flex flex-col">
          <AnimatePresence initial={false}>
            {todos.slice(0, 6).map((todo) => (
              <TodoRow key={todo.id} text={stripCitations(todo.text)} onDone={() => briefing.completeTodo(todo.id)} />
            ))}
          </AnimatePresence>
        </ul>
        <form onSubmit={submit} className="flex items-center gap-2 pt-0.5">
          <span aria-hidden className="text-[16px] leading-none text-ink-muted">
            +
          </span>
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Add a loop…"
            aria-label="Add a loop"
            className="selectable min-w-0 flex-1 bg-transparent text-[14px] text-ink outline-none placeholder:text-ink-muted"
          />
        </form>
      </div>
    </GlassCard>
  );
}

function TodayCard({ cards, colorFor }: { cards: TimelineCard[]; colorFor: (c?: string) => string }) {
  const activities = useMemo(() => cards.filter((c) => c.type === "card").reverse(), [cards]);

  return (
    <GlassCard aria-label="Today so far">
      <div className="flex flex-col gap-3">
        <CardTitle
          trailing={
            <span className="text-[12px] text-ink-muted">
              {activities.length} {activities.length === 1 ? "activity" : "activities"}
            </span>
          }
        >
          Today so far
        </CardTitle>
        {activities.length === 0 ? (
          <p className="text-[14px] text-ink-muted">Activity shows up here as Dayframe records your day.</p>
        ) : (
          <div className="no-scrollbar -mx-1 overflow-x-auto px-1 py-0.5">
            <ul className="flex gap-2.5">
              <AnimatePresence initial={false}>
                {activities.map((card) => (
                  <motion.li
                    key={card.key}
                    layout
                    initial={{ opacity: 0, x: -16, filter: "blur(6px)" }}
                    animate={{ opacity: 1, x: 0, filter: "blur(0px)" }}
                    exit={{ opacity: 0 }}
                    transition={settle}
                  >
                    <ActivityChip
                      title={card.title ?? "Activity"}
                      time={cardTime(card)}
                      category={card.category}
                      summary={card.summary}
                      color={colorFor(card.category)}
                    />
                  </motion.li>
                ))}
              </AnimatePresence>
            </ul>
          </div>
        )}
        {isEmbedded ? (
          <button
            type="button"
            onClick={() => postToHost({ type: "showTimeline" })}
            className="self-start text-[12px] text-ink-muted hover:text-ink-2"
          >
            Open Timeline
          </button>
        ) : null}
      </div>
    </GlassCard>
  );
}

function WeekCard({ briefing, colorFor }: { briefing: Briefing; colorFor: (c?: string) => string }) {
  const stats = briefing.state?.stats;
  const minutes = stats?.totalMinutes ?? 0;
  const top = Object.entries(stats?.byCategory ?? {}).sort((a, b) => b[1] - a[1])[0];
  const best = (stats?.bestHours ?? []).slice(0, 2).map(hourLabel).join(", ");

  return (
    <GlassCard aria-label="This week">
      <div className="flex flex-col gap-3">
        <CardTitle>This week</CardTitle>
        <div className="flex gap-2.5">
          <Stat value={<TickingDuration minutes={minutes} />} label="tracked" />
          <Stat value={best || "–"} label="best hours" />
        </div>
        {top ? (
          <p className="flex items-center gap-2 text-[13px] text-ink-2">
            <span aria-hidden className="size-2 rounded-full" style={{ background: colorFor(top[0]) }} />
            Most time: {top[0]}, {formatMinutes(top[1])}
          </p>
        ) : null}
      </div>
    </GlassCard>
  );
}

/** "3h 7m" where both numbers count up from zero the first time they appear. */
function TickingDuration({ minutes }: { minutes: number }) {
  const m = Math.max(0, Math.round(minutes));
  const ticker = "tracking-normal text-accent-text";
  return (
    <span aria-label={formatMinutes(m)}>
      {m >= 60 ? (
        <>
          <NumberTicker value={Math.floor(m / 60)} className={ticker} aria-hidden />
          <span aria-hidden>h </span>
        </>
      ) : null}
      <NumberTicker value={m % 60} className={ticker} aria-hidden />
      <span aria-hidden>m</span>
    </span>
  );
}

function AskCard({ briefing }: { briefing: Briefing }) {
  const [question, setQuestion] = useState("");

  const submit = (e: FormEvent) => {
    e.preventDefault();
    void briefing.ask(question);
  };

  return (
    <GlassCard aria-label="Ask your past" aria-busy={briefing.asking}>
      <div className="flex flex-col gap-3">
        <CardTitle>Ask your past</CardTitle>
        <form
          onSubmit={submit}
          className="flex items-center gap-2.5 rounded-chip border border-input-border bg-input px-3.5 py-2.5 focus-within:border-accent/60"
        >
          <Search className="size-4 shrink-0 text-ink-muted" aria-hidden />
          <input
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="What was I doing yesterday afternoon?"
            aria-label="Ask your past"
            className="selectable min-w-0 flex-1 bg-transparent text-[15px] text-ink outline-none placeholder:text-ink-muted"
          />
          <AnimatePresence initial={false}>
            {question.trim() || briefing.asking ? (
              <motion.span
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.9 }}
                transition={{ duration: duration.quick }}
              >
                <PillButton type="submit" prominent icon={ArrowUp} busy={briefing.asking}>
                  {briefing.asking ? "Searching" : "Ask"}
                </PillButton>
              </motion.span>
            ) : null}
          </AnimatePresence>
        </form>

        <AnimatePresence mode="wait" initial={false}>
          {briefing.asking ? (
            <motion.div key="asking" {...fold} className="overflow-hidden">
              <div className="rounded-chip border border-soft-border bg-soft p-3.5">
                <SkeletonParagraph lines={3} />
              </div>
            </motion.div>
          ) : briefing.answer ? (
            <motion.div key="answer" {...fold} className="overflow-hidden">
              <div className="flex flex-col gap-2 rounded-chip border border-soft-border bg-soft p-3.5">
                <Answer text={stripCitations(briefing.answer)} />
                <button
                  type="button"
                  onClick={briefing.clearAnswer}
                  className="self-start text-[12px] text-ink-muted hover:text-ink-2"
                >
                  Clear
                </button>
              </div>
            </motion.div>
          ) : null}
        </AnimatePresence>
      </div>
    </GlassCard>
  );
}

const fold = {
  initial: { opacity: 0, height: 0 },
  animate: { opacity: 1, height: "auto" },
  exit: { opacity: 0, height: 0 },
  transition: { duration: duration.base, ease: ease.outQuart },
} as const;

/** Plain-text rendering of the model's markdown-ish answer: paragraphs and bullet lists. */
function Answer({ text }: { text: string }) {
  const blocks = text
    .replace(/\*\*|__|`/g, "")
    .split(/\n{2,}/)
    .map((b) => b.trim())
    .filter(Boolean);

  return (
    <div className="flex flex-col gap-2 text-[14px] leading-relaxed text-ink">
      {blocks.map((block, i) => {
        const lines = block.split("\n");
        const isList = lines.every((l) => /^\s*([-*•]|\d+[.)])\s+/.test(l));
        return isList ? (
          <ul key={i} className="selectable ml-4 list-disc">
            {lines.map((l, j) => (
              <li key={j}>{l.replace(/^\s*([-*•]|\d+[.)])\s+/, "")}</li>
            ))}
          </ul>
        ) : (
          <p key={i}>
            <InkText text={block.replace(/\n/g, " ")} delay={i * 0.15} />
          </p>
        );
      })}
    </div>
  );
}
