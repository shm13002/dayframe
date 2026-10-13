// Briefing tab build. Served by briefing.py at http://127.0.0.1:<port>/app/
// (see Briefing/install.sh, which copies Briefing/dist into ~/Briefing/app/dist).
import { resolve } from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const briefingPort = Number(process.env.BRIEFING_PORT ?? 8765);

export default defineConfig({
  base: "/app/",
  plugins: [react(), tailwindcss()],
  resolve: { alias: { "@": resolve(import.meta.dirname, "src") } },
  build: {
    outDir: resolve(import.meta.dirname, "../Briefing/dist"),
    emptyOutDir: true,
    // briefing.py's CSP is default-src 'self': fonts and images must be real files, never data: URIs.
    assetsInlineLimit: 0,
    rollupOptions: {
      input: {
        index: resolve(import.meta.dirname, "index.html"),
        kit: resolve(import.meta.dirname, "kit.html"),
      },
    },
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      // briefing.py only accepts requests whose Host and Origin are its own address
      // (_ok_origin). Rewrite Host and drop Origin so dev requests look same-origin.
      "/api": {
        target: `http://127.0.0.1:${briefingPort}`,
        changeOrigin: true,
        configure: (proxy) => {
          proxy.on("proxyReq", (req) => req.removeHeader("origin"));
        },
      },
    },
  },
});
