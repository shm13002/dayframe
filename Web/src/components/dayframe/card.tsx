import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

interface GlassCardProps {
  children: ReactNode;
  /** Washes the card with the palette's soft accent (used for "Your next thing"). */
  tint?: boolean;
  className?: string;
  as?: "section" | "div" | "article";
  "aria-label"?: string;
  "aria-busy"?: boolean;
}

/** The standup glass card from Daily/Briefing (BriefingCardShell in Swift). */
export function GlassCard({ children, tint = false, className, as: Tag = "section", ...aria }: GlassCardProps) {
  return (
    <Tag
      {...aria}
      className={cn("relative rounded-card border border-shell-border p-[22px]", className)}
      style={{
        backgroundImage: tint
          ? "var(--df-shell-gradient), linear-gradient(var(--df-soft-fill), var(--df-soft-fill))"
          : "var(--df-shell-gradient)",
        boxShadow: "var(--df-shell-shadow), var(--df-shell-glow)",
      }}
    >
      {children}
    </Tag>
  );
}

interface CardTitleProps {
  children: ReactNode;
  trailing?: ReactNode;
  id?: string;
}

export function CardTitle({ children, trailing, id }: CardTitleProps) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <h2 id={id} className="font-serif text-[22px] leading-tight font-normal text-shell-heading">
        {children}
      </h2>
      {trailing}
    </div>
  );
}
