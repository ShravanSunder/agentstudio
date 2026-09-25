import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type {
  ChapterAnchorLandingObservation,
  ChapterAnchorLandingViewport,
} from "./chapter-anchor-browser-command";

declare module "vitest" {
  export interface ProvidedContext {
    siteHeaderBrowserTestUrl: string;
  }
}

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyChapterAnchorLanding(request: {
      readonly chapterId: string;
      readonly pageUrl: string;
      readonly viewports: readonly ChapterAnchorLandingViewport[];
    }): Promise<readonly ChapterAnchorLandingObservation[]>;
  }
}

describe("chapter URL anchors", () => {
  it("lands /#find-and-focus with the chapter heading below the sticky header", async () => {
    // Arrange
    const viewports = [
      { width: 1280, height: 800 },
      { width: 390, height: 844 },
    ] as const;

    // Act
    const observations = await commands.verifyChapterAnchorLanding({
      chapterId: "find-and-focus",
      pageUrl: inject("siteHeaderBrowserTestUrl"),
      viewports,
    });

    // Assert
    expect(observations).toHaveLength(viewports.length);
    for (const observation of observations) {
      const viewport = `${String(observation.viewport.width)}x${String(observation.viewport.height)}`;
      expect(observation.scrollY, viewport).toBeGreaterThan(0);
      expect(observation.chapterHeadingTop, viewport).toBeGreaterThanOrEqual(
        observation.headerBottom,
      );
      expect(observation.chapterTitleBottom, viewport).toBeLessThanOrEqual(
        observation.viewportHeight,
      );
    }
  }, 60_000);
});
