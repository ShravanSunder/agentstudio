import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

export default defineConfig({
  root: "dist",
  plugins: [cloudflare()],
});
