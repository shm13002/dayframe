import { motion } from "motion/react";
import type { ComponentType, ReactNode } from "react";
import { snappy } from "@/lib/motion";
import { cn } from "@/lib/utils";

type IconType = ComponentType<{ className?: string; "aria-hidden"?: boolean; strokeWidth?: number }>;

interface PillButtonProps {
  children: ReactNode;
  icon?: IconType;
  /** Filled with the palette's button color; otherwise a glass control. */
  prominent?: boolean;
  /** Shows a quiet spinner instead of the icon and blocks clicks. */
  busy?: boolean;
  disabled?: boolean;
  onClick?: () => void;
  type?: "button" | "submit";
  className?: string;
  "aria-label"?: string;
}

/** Capsule button used across Briefing (BriefingPill in Swift). */
export function PillButton({
  children,
  icon: Icon,
  prominent = false,
  busy = false,
  disabled = false,
  onClick,
  type = "button",
  className,
  ...aria
}: PillButtonProps) {
  const inactive = disabled || busy;
  return (
    <motion.button
      type={type}
      onClick={onClick}
      disabled={inactive}
      aria-busy={busy || undefined}
      whileTap={inactive ? undefined : { scale: 0.96 }}
      transition={snappy}
      className={cn(
        "inline-flex shrink-0 items-center gap-1.5 rounded-full border px-3.5 py-2 text-[13px] font-semibold",
        "transition-[filter,opacity] duration-150 disabled:cursor-default",
        prominent
          ? "border-button-border bg-button text-button-text shadow-[inset_0_0_4px_var(--df-button-glow)]"
          : "border-control-border bg-control text-control-text shadow-[inset_0_0_4px_var(--df-control-glow)]",
        !inactive && "hover:brightness-[1.04]",
        busy && "opacity-90",
        disabled && !busy && "opacity-50",
        className,
      )}
      {...aria}
    >
      {busy ? <Spinner /> : Icon ? <Icon aria-hidden className="size-3.5" strokeWidth={2.4} /> : null}
      {children}
    </motion.button>
  );
}

function Spinner() {
  return (
    <span
      aria-hidden
      className="size-3.5 animate-spin rounded-full border-2 border-current border-t-transparent opacity-80 motion-reduce:animate-none"
    />
  );
}
