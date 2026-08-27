import { defineWorker } from "@cloudflare/vite-plugin/experimental-config";

export default defineWorker({
  name: "agent-studio-web",
  compatibilityDate: "2026-08-20",
  assets: {
    htmlHandling: "drop-trailing-slash",
    notFoundHandling: "none",
  },
});
