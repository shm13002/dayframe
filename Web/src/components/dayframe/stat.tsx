import type { ReactNode } from "react";

/** A big serif value over a small label (BriefingStat in Swift). */
export function Stat({ value, label }: { value: ReactNode; label: string }) {
  return (
    <div className="flex min-w-0 flex-1 flex-col gap-0.5 rounded-chip border border-stat-border bg-stat p-3">
      <span className="truncate font-serif text-[26px] leading-none text-accent-text tabular-nums">{value}</span>
      <span className="text-[12px] text-ink-muted">{label}</span>
    </div>
  );
}
