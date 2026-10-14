import { MotionConfig } from "motion/react";
import { StrictMode, useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "@/theme/tokens.css";
import { connectHost, initialContext, type JarvisContext, postToHost } from "./host";
import { JarvisPage } from "./jarvis-page";
import { useJarvis } from "./use-jarvis";

function App() {
  const [context, setContext] = useState<JarvisContext>(initialContext);
  const jarvis = useJarvis(context);
  const sendRef = useRef(jarvis.send);
  sendRef.current = jarvis.send;
  const ask = useCallback((text: string, surface: "voice" | "chat") => void sendRef.current(text, surface), []);

  useEffect(() => connectHost(setContext, ask), [ask]);
  useEffect(() => {
    postToHost({ type: "ready" });
  }, []);

  return (
    <MotionConfig reducedMotion="user">
      <JarvisPage jarvis={jarvis} context={context} />
    </MotionConfig>
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
