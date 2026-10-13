// Dayframe's motion vocabulary ("ink & paper"): things settle like ink, never bounce
// on data. Use these instead of inline numbers so timing stays consistent.
import type { Transition } from "motion/react";

export const duration = {
  quick: 0.15,
  base: 0.24,
  slow: 0.42,
} as const;

export const ease = {
  outQuart: [0.25, 1, 0.5, 1],
  settle: [0.2, 0.8, 0.2, 1],
} as const;

/** Layout and size changes. Critically damped: no overshoot. */
export const settle: Transition = { type: "spring", stiffness: 260, damping: 32, mass: 1 };

/** Direct touch feedback (press/hover) may overshoot a touch. */
export const snappy: Transition = { type: "spring", stiffness: 420, damping: 26, mass: 0.8 };

/** Content entering: blur to sharp, slight rise. */
export const enter = {
  initial: { opacity: 0, y: 8, filter: "blur(6px)" },
  animate: { opacity: 1, y: 0, filter: "blur(0px)" },
  exit: { opacity: 0, y: -4, filter: "blur(4px)" },
  transition: { duration: duration.slow, ease: ease.outQuart },
} as const;

export const stagger = 0.05;
