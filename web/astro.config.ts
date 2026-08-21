import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
  output: "static",
  vite: {
    plugins: [tailwindcss()],
    server: {
      watch: {
        interval: 100,
        usePolling: true,
      },
    },
  },
});
