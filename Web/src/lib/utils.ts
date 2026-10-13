import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

/** shadcn's class helper: merge conditional classes, later Tailwind classes win. */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/** "1h 48m" / "45m", like durationLabel in BriefingView.swift. */
export function formatMinutes(minutes: number): string {
  const m = Math.max(0, Math.round(minutes));
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;
}

export function greeting(date = new Date()): string {
  const hour = date.getHours();
  return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
}
