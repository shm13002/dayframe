import { MotionConfig } from "motion/react";
import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { PillButton } from "@/components/dayframe/pill-button";
import { SkeletonParagraph } from "@/components/dayframe/skeleton";
import { connectHost, type HostContext, initialContext, postToHost } from "@/lib/bridge";
import "@/theme/tokens.css";
import { BriefingPage } from "./briefing-page";
import { useBriefing } from "./use-briefing";

function App() {
  const [context, setContext] = useState<HostContext>(initialContext);
  const briefing = useBriefing();

  useEffect(() => connectHost(setContext), []);

  // Tell the app the page is alive once there is something to show; it falls back
  // to the native Briefing screen if this never arrives.
  useEffect(() => {
    if (briefing.phase === "ready") postToHost({ type: "ready" });
  }, [briefing.phase]);

  return (
    <MotionConfig reducedMotion="user">
      {briefing.phase === "ready" ? (
        <BriefingPage briefing={briefing} categories={context.categories} />
      ) : briefing.phase === "offline" ? (
        <Offline onRetry={briefing.refresh} />
      ) : (
        <div className="mx-auto max-w-[720px] px-11 pt-16" aria-busy>
          <SkeletonParagraph lines={3} />
        </div>
      )}
    </MotionConfig>
  );
}

function Offline({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="grid h-full place-items-center px-8">
      <div className="flex max-w-[420px] flex-col items-start gap-3">
        <h1 className="font-serif text-[28px] text-ink">Briefing isn't running</h1>
        <p className="text-[14px] leading-relaxed text-ink-2">
          The Briefing service on this Mac didn't answer. It usually starts by itself; give it a moment, then try again.
        </p>
        <PillButton prominent onClick={onRetry}>
          Try again
        </PillButton>
      </div>
    </div>
  );
}

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
