import { motion, useReducedMotion } from "motion/react";
import { useMemo } from "react";
import { ease } from "@/lib/motion";
import { cn } from "@/lib/utils";

interface InkTextProps {
  text: string;
  className?: string;
  /** Seconds between words. The whole reveal is capped at ~1.2 s however long the text is. */
  stagger?: number;
  delay?: number;
}

/**
 * Words settle onto the page like ink: each one comes into focus from a soft blur.
 * Remount (change `key`) to replay, e.g. when a new briefing arrives.
 */
export function InkText({ text, className, stagger = 0.022, delay = 0 }: InkTextProps) {
  const reduce = useReducedMotion();
  const words = useMemo(() => text.split(/(\s+)/).filter((w) => w.length > 0), [text]);
  const step = Math.min(stagger, 1.2 / Math.max(words.length, 1));

  if (reduce) return <span className={className}>{text}</span>;

  return (
    <span className={cn("selectable", className)}>
      <span className="sr-only">{text}</span>
      {words.map((word, i) =>
        /^\s+$/.test(word) ? (
          <span key={i} aria-hidden>
            {word}
          </span>
        ) : (
          <motion.span
            key={i}
            aria-hidden
            className="inline-block"
            initial={{ opacity: 0, filter: "blur(5px)", y: 3 }}
            animate={{ opacity: 1, filter: "blur(0px)", y: 0 }}
            transition={{ duration: 0.5, ease: ease.outQuart, delay: delay + i * step }}
          >
            {word}
          </motion.span>
        ),
      )}
    </span>
  );
}
