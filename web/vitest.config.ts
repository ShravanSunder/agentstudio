import { playwright } from "@vitest/browser-playwright";
import { defineConfig } from "vitest/config";

import { verifyChapterAnchorLanding } from "./tests/chapter-anchor-browser-command.ts";
import {
  verifyChapterAutoplayAtNaturalFraming,
  verifyChapterSceneClicks,
} from "./tests/chapter-autoplay-browser-command.ts";
import { verifyChapterScrollGeometry } from "./tests/chapter-scroll-geometry-browser-command.ts";
import {
  verifyChapterStepRow,
  verifySingleStepChapter,
  verifyChapterTitleAnchors,
} from "./tests/chapter-surface-browser-command.ts";
import {
  verifyHeroIntroLayout,
  verifyHeroIntroPlayback,
  verifyHeroIntroShift,
} from "./tests/hero-intro-browser-command.ts";
import { verifyHeroIntroFinale } from "./tests/hero-intro-finale-browser-command.ts";
import { verifyRailViewportBands } from "./tests/rail-band-browser-command.ts";
import { buildSceneBundlesForBrowserTest } from "./tests/scene-bundle-browser-command.ts";
import { verifySiteFooterResponsiveLayout } from "./tests/site-footer-browser-command.ts";
import { verifySiteHeaderScrollStability } from "./tests/site-header-browser-command.ts";
import { verifyTopologyEnd } from "./tests/topology-end-browser-command.ts";
import { verifyTopologyNodeVocabulary } from "./tests/topology-node-vocabulary-browser-command.ts";
import { verifyWebsiteQualityLayout } from "./tests/website-quality-browser-command.ts";

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
        // Pre-bundle GSAP up front so the first browser run does not discover it
        // mid-run and reload the test page.
        optimizeDeps: { include: ["gsap"] },
        test: {
          name: "browser",
          include: ["tests/**/*.browser.test.ts"],
          browser: {
            commands: {
              buildSceneBundlesForBrowserTest,
              verifyRailViewportBands,
              verifyChapterAnchorLanding,
              verifyChapterAutoplayAtNaturalFraming,
              verifyChapterSceneClicks,
              verifyChapterScrollGeometry,
              verifyHeroIntroLayout,
              verifyHeroIntroPlayback,
              verifyHeroIntroShift,
              verifyHeroIntroFinale,
              verifyChapterStepRow,
              verifySingleStepChapter,
              verifyChapterTitleAnchors,
              verifySiteFooterResponsiveLayout,
              verifySiteHeaderScrollStability,
              verifyTopologyEnd,
              verifyTopologyNodeVocabulary,
              verifyWebsiteQualityLayout,
            },
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
