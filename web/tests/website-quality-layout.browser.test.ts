import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import { chapterCatalog } from "../src/chapters/chapter-catalog";
import type { WebsiteLayoutObservation } from "./website-quality-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyWebsiteQualityLayout(pageUrl: string): Promise<readonly WebsiteLayoutObservation[]>;
  }
}

it("renders every chapter with unclipped headings and no sideways scroll at every width", async () => {
  // Act
  const observations = await commands.verifyWebsiteQualityLayout(
    inject("siteHeaderBrowserTestUrl"),
  );

  // Assert
  expect(observations).toHaveLength(8);
  for (const observation of observations) {
    const width = `${String(observation.width)}px`;
    expect(observation.chapterCount, width).toBe(chapterCatalog.length);
    expect(observation.clippedHeadings, width).toEqual([]);
    expect(observation.horizontalOverflow, width).toBeLessThanOrEqual(1);
  }
}, 60_000);
