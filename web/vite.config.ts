import { resolve } from "node:path";

import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

import {
  campaignAttributionRegistry,
  campaignChannels,
} from "./src/campaign-attribution/campaign-attribution-registry.ts";

const astroOutputDirectory = resolve(import.meta.dirname, "dist");
const campaignHtmlEntries = Object.fromEntries([
  ...campaignChannels.map((channel) => [
    `channel-${channel}`,
    resolve(astroOutputDirectory, channel, "index.html"),
  ]),
  ...campaignAttributionRegistry.routes.map((route) => [
    `campaign-${route.channel}-${route.code}`,
    resolve(astroOutputDirectory, route.path.slice(1), "index.html"),
  ]),
]);

export default defineConfig({
  root: "dist",
  environments: {
    client: {
      build: {
        rolldownOptions: {
          input: {
            home: resolve(astroOutputDirectory, "index.html"),
            ...campaignHtmlEntries,
          },
        },
      },
    },
  },
  plugins: [cloudflare()],
});
