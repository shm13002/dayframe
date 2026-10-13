import { CheckCircle2, Circle } from "lucide-react";
import { motion } from "motion/react";
import { useState } from "react";
import { duration, ease } from "@/lib/motion";
import { cn } from "@/lib/utils";

interface TodoRowProps {
  text: string;
  /** Called once the strike-through has drawn, so the row can fold away. */
  onDone: () => void;
}

/** An open loop. Checking it draws a line through the text, then the row folds up. */
export function TodoRow({ text, onDone }: TodoRowProps) {
  const [checked, setChecked] = useState(false);

  return (
    <motion.li
      layout
      initial={{ opacity: 0, height: 0 }}
      animate={{ opacity: 1, height: "auto" }}
      exit={{ opacity: 0, height: 0, transition: { duration: duration.base, ease: ease.outQuart } }}
      className="overflow-hidden"
    >
      <div className="flex items-start gap-2.5 py-1">
        <button
          type="button"
          role="checkbox"
          aria-checked={checked}
          aria-label={`Done: ${text}`}
          disabled={checked}
          onClick={() => setChecked(true)}
          className={cn("mt-px shrink-0 rounded-full", checked ? "text-accent" : "text-ink-muted hover:text-ink-2")}
        >
          {checked ? <CheckCircle2 className="size-4" aria-hidden /> : <Circle className="size-4" aria-hidden />}
        </button>
        <span className={cn("relative text-[14px] leading-snug", checked ? "text-ink-muted" : "text-ink")}>
          {text}
          <motion.span
            aria-hidden
            className="absolute top-1/2 left-0 h-px w-full origin-left bg-current"
            initial={false}
            animate={{ scaleX: checked ? 1 : 0 }}
            transition={{ duration: 0.28, ease: ease.outQuart }}
            onAnimationComplete={() => {
              if (checked) onDone();
            }}
          />
        </span>
      </div>
    </motion.li>
  );
}
