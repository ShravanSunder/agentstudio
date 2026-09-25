import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { HeroLayoutObservation } from "./hero-intro-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyHeroIntroLayout(
      pageUrl: string,
      viewports: readonly { readonly width: number; readonly height: number }[],
    ): Promise<HeroLayoutObservation[]>;
  }
}

const viewports = [
  { width: 390, height: 844 },
  { width: 820, height: 1180 },
  { width: 1024, height: 768 },
  { width: 1280, height: 800 },
  { width: 1366, height: 768 },
  { width: 1440, height: 900 },
  { width: 1512, height: 982 },
  { width: 1600, height: 1000 },
  { width: 1728, height: 1117 },
  { width: 1920, height: 1080 },
  { width: 2560, height: 1440 },
] as const;

describe("hero intro", () => {
  it("keeps the settled terminal, install box and canvas correct at every approved size", async () => {
    const observations = await commands.verifyHeroIntroLayout(
      inject("siteHeaderBrowserTestUrl"),
      viewports,
    );
    for (const observation of observations) {
      expect(observation.rowsInsideWindow, observation.viewport).toBe(true);
      expect(
        observation.installBottom,
        `${observation.viewport}: headline ${observation.headlineBottom}, column ${observation.columnTop}, root ${observation.rootTop}, window ${observation.windowTop}-${observation.windowBottom}`,
      ).toBeLessThanOrEqual(Number(observation.viewport.split("x")[1]));
      expect(
        Math.abs(observation.windowLeft - observation.appLeft),
        observation.viewport,
      ).toBeLessThanOrEqual(1);
      expect(
        Math.abs(observation.windowRight - observation.appRight),
        observation.viewport,
      ).toBeLessThanOrEqual(1);
      expect(observation.cursorCount, observation.viewport).toBe(1);
      expect(
        observation.documentWidth,
        `${observation.viewport}: ${observation.overflowElements.join(", ")}`,
      ).toBe(observation.viewportWidth);
      expect(observation.codexVisible, observation.viewport).toBe(
        Number(observation.viewport.split("x")[0]) >= 1024,
      );
      expect(observation.canvasColor, observation.viewport).toBe("rgb(25, 27, 31)");
      expect(observation.visibleBashRows, observation.viewport).toBe(1);
      if (observation.viewport === "820x1180") {
        expect(observation.earlierExchangeVisible).toBe(true);
      }
    }
  });
});
