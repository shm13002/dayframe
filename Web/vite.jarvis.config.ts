// Jarvis tab build: one self-contained HTML file the app bundles and loads from disk.
// A file:// page is a non-web origin, which Hermes's WebSocket guard trusts (the session
// token is the boundary), so the page talks to Hermes directly.
import { resolve } from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  root: resolve(import.meta.dirname, "src/jarvis"),
  plugins: [react(), tailwindcss(), viteSingleFile()],
  resolve: { alias: { "@": resolve(import.meta.dirname, "src") } },
  build: {
    outDir: resolve(import.meta.dirname, "../App/Dayflow/Jarvis/Resources"),
    emptyOutDir: true,
    target: "safari17",
    rollupOptions: { input: resolve(import.meta.dirname, "src/jarvis/jarvis.html") },
  },
  server: { port: 5175, strictPort: true },
});
