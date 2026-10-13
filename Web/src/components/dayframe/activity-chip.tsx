import { cn } from "@/lib/utils";

interface ActivityChipProps {
  title: string;
  time: string;
  category?: string;
  color: string;
  summary?: string;
  className?: string;
}

/** One timeline card in the "Today so far" strip (BriefingActivityChip in Swift). */
export function ActivityChip({ title, time, category, color, summary, className }: ActivityChipProps) {
  return (
    <article
      title={summary}
      className={cn(
        "flex min-h-[84px] w-[170px] shrink-0 flex-col gap-1.5 rounded-chip border bg-card p-3",
        className,
      )}
      style={{ borderColor: `color-mix(in srgb, ${color} 45%, transparent)` }}
    >
      <span className="flex items-center gap-1.5 text-[11px] font-medium text-card-time">
        <span aria-hidden className="size-[7px] rounded-full" style={{ background: color }} />
        {time}
      </span>
      <h3 className="line-clamp-2 text-[13px] leading-snug font-semibold text-card-title">{title}</h3>
      {category ? <span className="text-[11px] text-ink-muted">{category}</span> : null}
    </article>
  );
}
