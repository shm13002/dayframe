// Welcome show build ("System Awakening"): one self-contained HTML file that the app
// bundles next to island.html and loads with loadFileURL.
import { resolve } from "node:path";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  root: resolve(import.meta.dirname, "src/welcome"),
  plugins: [viteSingleFile()],
  build: {
    outDir: resolve(import.meta.dirname, "../App/Dayflow/Welcome/Resources"),
    // The folder also holds the sound files, so never empty it.
    emptyOutDir: false,
    target: "safari17",
    rollupOptions: { input: resolve(import.meta.dirname, "src/welcome/welcome.html") },
  },
  server: { port: 5175, strictPort: true },
});
