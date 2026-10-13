// Notch-island show build: one self-contained HTML file (scripts and styles inlined)
// that the app bundles and loads with loadHTMLString, so it works even when the
// Briefing service is down.
import { resolve } from "node:path";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  root: resolve(import.meta.dirname, "src/island"),
  plugins: [viteSingleFile()],
  build: {
    outDir: resolve(import.meta.dirname, "../App/Dayflow/Island/Resources"),
    emptyOutDir: true,
    target: "safari17",
    rollupOptions: { input: resolve(import.meta.dirname, "src/island/island.html") },
  },
  server: { port: 5174, strictPort: true },
});
