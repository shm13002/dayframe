import { cn } from "@/lib/utils";

/** A text-shaped placeholder with a slow sheen. Used while the model writes. */
export function SkeletonLine({ className }: { className?: string }) {
  return (
    <span
      aria-hidden
      className={cn(
        "relative block h-3.5 overflow-hidden rounded-full bg-[color-mix(in_srgb,var(--df-text-primary)_8%,transparent)]",
        className,
      )}
    >
      <span className="df-sheen absolute inset-0" />
    </span>
  );
}

export function SkeletonParagraph({ lines = 3 }: { lines?: number }) {
  const widths = ["w-full", "w-[92%]", "w-[78%]", "w-[85%]", "w-[60%]"];
  return (
    <span className="flex flex-col gap-2.5 py-1">
      {Array.from({ length: lines }, (_, i) => (
        <SkeletonLine key={i} className={widths[i % widths.length]} />
      ))}
    </span>
  );
}
