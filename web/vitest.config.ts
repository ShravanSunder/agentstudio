import { playwright } from "@vitest/browser-playwright";
import { defineConfig } from "vitest/config";

import { verifySiteFooterResponsiveLayout } from "./tests/site-footer-browser-command.ts";
import { verifySiteHeaderScrollStability } from "./tests/site-header-browser-command.ts";

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: "unit",
          include: ["tests/**/*.test.ts"],
          exclude: ["tests/**/*.browser.test.ts"],
        },
      },
      {
        test: {
          name: "browser",
          include: ["tests/**/*.browser.test.ts"],
          browser: {
            commands: { verifySiteFooterResponsiveLayout, verifySiteHeaderScrollStability },
            enabled: true,
            provider: playwright({ launchOptions: { channel: "chrome" } }),
            headless: true,
            instances: [{ browser: "chromium" }],
          },
          globalSetup: ["./tests/site-header-browser-global-setup.ts"],
        },
      },
    ],
  },
});
