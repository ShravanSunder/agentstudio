import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

import { siteMetadata } from "./src/site-metadata";

export default defineConfig({
  output: "static",
  site: siteMetadata.canonicalOrigin,
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
