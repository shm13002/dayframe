// Dayframe UI kit gallery: every token and component in one page, for design review
// and for /design-sync (Claude Design). Served at /app/kit.html; not used by the app.
import { Sparkles, Target, Undo2 } from "lucide-react";
import { MotionConfig } from "motion/react";
import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { ActivityChip } from "@/components/dayframe/activity-chip";
import { CardTitle, GlassCard } from "@/components/dayframe/card";
import { InkText } from "@/components/dayframe/ink-text";
import { PillButton } from "@/components/dayframe/pill-button";
import { SkeletonParagraph } from "@/components/dayframe/skeleton";
import { Stat } from "@/components/dayframe/stat";
import { TodoRow } from "@/components/dayframe/todo-row";
import { applyTheme, type Mode, PALETTES, type PaletteName, paletteTokens } from "@/theme/palettes";
import "@/theme/tokens.css";

const SAMPLE =
  "You were redesigning Dayframe's Briefing screen and had just wired the palette tokens into the web build.";

function Kit() {
  const [palette, setPalette] = useState<PaletteName>("original");
  const [mode, setMode] = useState<Mode>("light");
  const [replay, setReplay] = useState(0);

  useEffect(() => applyTheme(palette, mode), [palette, mode]);

  return (
    <MotionConfig reducedMotion="user">
      <main className="mx-auto flex max-w-[980px] flex-col gap-8 px-8 py-10">
        <header className="flex flex-wrap items-end gap-4">
          <div className="mr-auto">
            <h1 className="font-serif text-[34px] leading-none text-ink">Dayframe UI kit</h1>
            <p className="mt-1 text-[13px] text-ink-2">Figtree for reading, Instrument Serif for the things worth noticing.</p>
          </div>
          <label className="text-[13px] text-ink-2">
            Palette{" "}
            <select
              value={palette}
              onChange={(e) => setPalette(e.target.value as PaletteName)}
              className="rounded-md border border-input-border bg-input px-2 py-1 text-ink"
            >
              {PALETTES.map((p) => (
                <option key={p}>{p}</option>
              ))}
            </select>
          </label>
          <PillButton onClick={() => setMode(mode === "light" ? "dark" : "light")}>
            {mode === "light" ? "Dark" : "Light"} mode
          </PillButton>
        </header>

        <section aria-labelledby="palettes" className="flex flex-col gap-3">
          <h2 id="palettes" className="font-serif text-[22px] text-shell-heading">Palettes</h2>
          <div className="grid grid-cols-3 gap-3 sm:grid-cols-6">
            {PALETTES.map((p) => {
              const t = paletteTokens(p, mode);
              return (
                <button
                  key={p}
                  type="button"
                  onClick={() => setPalette(p)}
                  aria-pressed={palette === p}
                  className="flex flex-col gap-2 rounded-chip border border-card-border/50 p-2 text-left aria-pressed:border-accent"
                >
                  <span className="h-14 rounded-md" style={{ background: t.windowBackground }} />
                  <span className="flex gap-1">
                    {[t.accent, t.buttonFill, t.controlFill, t.softFill].map((c) => (
                      <span key={c} className="size-4 rounded-full border border-black/5" style={{ background: c }} />
                    ))}
                  </span>
                  <span className="text-[12px] text-ink capitalize">{p}</span>
                </button>
              );
            })}
          </div>
        </section>

        <section aria-labelledby="type" className="flex flex-col gap-2">
          <h2 id="type" className="font-serif text-[22px] text-shell-heading">Type</h2>
          <p className="font-serif text-[30px] leading-none text-ink">Monday, October 12</p>
          <p className="font-serif text-[24px] text-ink">Your next thing, in serif</p>
          <p className="text-[17px] text-ink">Body text at 17 for the briefing itself.</p>
          <p className="text-[14px] text-ink-2">Secondary text at 14.</p>
          <p className="text-[12px] text-ink-muted">Muted labels at 12.</p>
        </section>

        <section aria-labelledby="components" className="grid gap-[18px] md:grid-cols-[minmax(0,1fr)_340px]">
          <h2 id="components" className="sr-only">Components</h2>
          <GlassCard>
            <div className="flex flex-col gap-4">
              <CardTitle trailing={<PillButton onClick={() => setReplay((r) => r + 1)}>Replay ink</PillButton>}>
                Where you left off
              </CardTitle>
              <p className="text-[17px] leading-[1.6] text-ink">
                <InkText key={replay} text={SAMPLE} />
              </p>
              <div className="flex flex-wrap gap-2.5">
                <PillButton prominent icon={Sparkles}>New briefing</PillButton>
                <PillButton prominent busy>Writing…</PillButton>
                <PillButton icon={Undo2}>Resume my apps</PillButton>
                <PillButton disabled>Disabled</PillButton>
              </div>
            </div>
          </GlassCard>
          <GlassCard tint>
            <div className="flex flex-col gap-3.5">
              <CardTitle>Your next thing</CardTitle>
              <p className="font-serif text-[24px] leading-[1.25] text-ink">Wire the notch island into the build.</p>
              <span className="inline-flex items-center gap-2 self-start rounded-full border border-control-border bg-control px-3 py-1.5 text-[13px] font-medium text-control-text">
                <Target className="size-3.5" aria-hidden /> Ship the redesign
              </span>
            </div>
          </GlassCard>
          <GlassCard>
            <div className="flex flex-col gap-3">
              <CardTitle>Open loops</CardTitle>
              <ul>
                <TodoRow key={`a${replay}`} text="Check recording after install" onDone={() => undefined} />
                <TodoRow key={`b${replay}`} text="Run /design-sync" onDone={() => undefined} />
              </ul>
              <SkeletonParagraph lines={2} />
            </div>
          </GlassCard>
          <GlassCard>
            <div className="flex flex-col gap-3">
              <CardTitle>This week</CardTitle>
              <div className="flex gap-2.5">
                <Stat value="3h 7m" label="tracked" />
                <Stat value="11 AM" label="best hours" />
              </div>
              <div className="flex gap-2.5 overflow-x-auto">
                <ActivityChip title="Designing Dayframe UI" time="5:49 – 5:59 PM" category="Studying" color="#7B83FF" />
                <ActivityChip title="Assignments" time="2:40 – 2:48 PM" category="Assignments" color="#7FD3E8" />
              </div>
            </div>
          </GlassCard>
        </section>
      </main>
    </MotionConfig>
  );
}

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <StrictMode>
      <Kit />
    </StrictMode>,
  );
}
