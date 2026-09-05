import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { WebsiteLayoutObservation } from "./website-quality-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyWebsiteQualityLayout(pageUrl: string): Promise<readonly WebsiteLayoutObservation[]>;
  }
}

it("keeps hero copy visible and centers every desktop slideshow image", async () => {
  const observations = await commands.verifyWebsiteQualityLayout(
    inject("siteHeaderBrowserTestUrl"),
  );

  expect(observations).toHaveLength(35);
  for (const observation of observations) {
    const state = `${observation.width}px ${observation.story}`;
    expect(observation.clippedHeadline, state).toBe(false);
    expect(observation.horizontalOverflow, state).toBeLessThanOrEqual(1);
    if (observation.width >= 1024) {
      expect(observation.imageCenterOffset, state).toBeLessThanOrEqual(1);
    }
  }
}, 60_000);
